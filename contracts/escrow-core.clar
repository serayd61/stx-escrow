;; STX Escrow - Core Contract
;; Trustless escrow system for peer-to-peer transactions
;; 
;; Features:
;; - Create, fund, release, refund escrows
;; - Time-locked refunds
;; - Fee collection

;; ============================================
;; Constants
;; ============================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u1))
(define-constant ERR_INVALID_AMOUNT (err u2))
(define-constant ERR_ESCROW_NOT_FOUND (err u3))
(define-constant ERR_ALREADY_FUNDED (err u4))
(define-constant ERR_NOT_FUNDED (err u5))
(define-constant ERR_INVALID_STATE (err u6))
(define-constant ERR_NOT_BUYER (err u7))
(define-constant ERR_NOT_SELLER (err u8))
(define-constant ERR_TIMEOUT_NOT_REACHED (err u9))
(define-constant ERR_ESCROW_EXPIRED (err u10))
(define-constant ERR_PAUSED (err u11))
(define-constant ERR_TRANSFER_FAILED (err u12))

;; Escrow states
(define-constant STATE_CREATED u1)
(define-constant STATE_FUNDED u2)
(define-constant STATE_RELEASED u3)
(define-constant STATE_REFUNDED u4)
(define-constant STATE_DISPUTED u5)
(define-constant STATE_CANCELLED u6)

;; Fee: 0.5% = 50 basis points
(define-constant FEE_BASIS_POINTS u50)
(define-constant BASIS_POINTS_DENOMINATOR u10000)

;; Minimum escrow amount: 0.1 STX
(define-constant MIN_ESCROW_AMOUNT u100000)

;; ============================================
;; Data Variables
;; ============================================

(define-data-var contract-paused bool false)
(define-data-var escrow-counter uint u0)
(define-data-var total-volume uint u0)
(define-data-var fee-collector principal CONTRACT_OWNER)
(define-data-var collected-fees uint u0)

;; ============================================
;; Data Maps
;; ============================================

;; Main escrow storage
(define-map escrows
  { escrow-id: uint }
  {
    buyer: principal,
    seller: principal,
    amount: uint,
    fee: uint,
    state: uint,
    created-at: uint,
    funded-at: uint,
    timeout-blocks: uint,
    memo: (string-ascii 100),
    release-hash: (optional (buff 32))
  }
)

;; User escrow tracking
(define-map user-escrows
  { user: principal }
  { 
    as-buyer: (list 50 uint),
    as-seller: (list 50 uint),
    total-volume: uint
  }
)

;; ============================================
;; Private Functions
;; ============================================

;; Calculate fee
(define-private (calculate-fee (amount uint))
  (/ (* amount FEE_BASIS_POINTS) BASIS_POINTS_DENOMINATOR)
)

;; Check if escrow is expired
(define-private (is-expired (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow
    (and 
      (is-eq (get state escrow) STATE_FUNDED)
      (> stacks-block-height (+ (get funded-at escrow) (get timeout-blocks escrow)))
    )
    false
  )
)

;; ============================================
;; Read-Only Functions
;; ============================================

;; Get escrow details
(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows { escrow-id: escrow-id })
)

;; Get escrow status
(define-read-only (get-escrow-status (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow (ok (get state escrow))
    ERR_ESCROW_NOT_FOUND
  )
)

;; Get total escrow count
(define-read-only (get-escrow-count)
  (var-get escrow-counter)
)

;; Get total volume
(define-read-only (get-total-volume)
  (var-get total-volume)
)

;; Get collected fees
(define-read-only (get-collected-fees)
  (var-get collected-fees)
)

;; Check if user is buyer
(define-read-only (is-buyer (escrow-id uint) (user principal))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow (is-eq (get buyer escrow) user)
    false
  )
)

;; Check if user is seller
(define-read-only (is-seller (escrow-id uint) (user principal))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow (is-eq (get seller escrow) user)
    false
  )
)

;; Get user escrow stats
(define-read-only (get-user-stats (user principal))
  (default-to 
    { as-buyer: (list), as-seller: (list), total-volume: u0 }
    (map-get? user-escrows { user: user })
  )
)

;; Check if contract is paused
(define-read-only (is-paused)
  (var-get contract-paused)
)

;; ============================================
;; Public Functions - Escrow Operations
;; ============================================

;; Create a new escrow
(define-public (create-escrow 
  (seller principal) 
  (amount uint) 
  (timeout-blocks uint)
  (memo (string-ascii 100)))
  (let (
    (buyer tx-sender)
    (escrow-id (+ (var-get escrow-counter) u1))
    (fee (calculate-fee amount))
  )
    ;; Validations
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (>= amount MIN_ESCROW_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq buyer seller)) ERR_NOT_AUTHORIZED)
    (asserts! (> timeout-blocks u0) ERR_INVALID_AMOUNT)
    
    ;; Create escrow record
    (map-set escrows
      { escrow-id: escrow-id }
      {
        buyer: buyer,
        seller: seller,
        amount: amount,
        fee: fee,
        state: STATE_CREATED,
        created-at: stacks-block-height,
        funded-at: u0,
        timeout-blocks: timeout-blocks,
        memo: memo,
        release-hash: none
      }
    )
    
    ;; Update counter
    (var-set escrow-counter escrow-id)
    
    (ok { escrow-id: escrow-id, amount: amount, fee: fee })
  )
)

;; Fund an escrow (buyer deposits funds)
(define-public (fund-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (buyer (get buyer escrow))
    (total-amount (+ (get amount escrow) (get fee escrow)))
  )
    ;; Validations
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (is-eq tx-sender buyer) ERR_NOT_BUYER)
    (asserts! (is-eq (get state escrow) STATE_CREATED) ERR_ALREADY_FUNDED)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    
    ;; Update escrow state
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow {
        state: STATE_FUNDED,
        funded-at: stacks-block-height
      })
    )
    
    ;; Update total volume
    (var-set total-volume (+ (var-get total-volume) (get amount escrow)))
    
    (ok { escrow-id: escrow-id, amount: total-amount })
  )
)

;; Release funds to seller (buyer confirms receipt)
(define-public (release-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (buyer (get buyer escrow))
    (seller (get seller escrow))
    (amount (get amount escrow))
    (fee (get fee escrow))
  )
    ;; Validations
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (is-eq tx-sender buyer) ERR_NOT_BUYER)
    (asserts! (is-eq (get state escrow) STATE_FUNDED) ERR_NOT_FUNDED)
    
    ;; Transfer amount to seller
    (try! (as-contract (stx-transfer? amount tx-sender seller)))
    
    ;; Transfer fee to collector
    (try! (as-contract (stx-transfer? fee tx-sender (var-get fee-collector))))
    
    ;; Update escrow state
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { state: STATE_RELEASED })
    )
    
    ;; Update collected fees
    (var-set collected-fees (+ (var-get collected-fees) fee))
    
    (ok { escrow-id: escrow-id, released-to: seller, amount: amount })
  )
)

;; Request refund (buyer can claim after timeout)
(define-public (request-refund (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (buyer (get buyer escrow))
    (total-amount (+ (get amount escrow) (get fee escrow)))
  )
    ;; Validations
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (is-eq tx-sender buyer) ERR_NOT_BUYER)
    (asserts! (is-eq (get state escrow) STATE_FUNDED) ERR_NOT_FUNDED)
    (asserts! (is-expired escrow-id) ERR_TIMEOUT_NOT_REACHED)
    
    ;; Transfer back to buyer
    (try! (as-contract (stx-transfer? total-amount tx-sender buyer)))
    
    ;; Update escrow state
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { state: STATE_REFUNDED })
    )
    
    (ok { escrow-id: escrow-id, refunded-to: buyer, amount: total-amount })
  )
)

;; Cancel unfunded escrow
(define-public (cancel-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (buyer (get buyer escrow))
  )
    ;; Validations
    (asserts! (is-eq tx-sender buyer) ERR_NOT_BUYER)
    (asserts! (is-eq (get state escrow) STATE_CREATED) ERR_ALREADY_FUNDED)
    
    ;; Update escrow state
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { state: STATE_CANCELLED })
    )
    
    (ok escrow-id)
  )
)

;; Mutual refund (both parties agree)
(define-public (mutual-refund (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (seller (get seller escrow))
    (buyer (get buyer escrow))
    (total-amount (+ (get amount escrow) (get fee escrow)))
  )
    ;; Only seller can initiate mutual refund
    (asserts! (is-eq tx-sender seller) ERR_NOT_SELLER)
    (asserts! (is-eq (get state escrow) STATE_FUNDED) ERR_NOT_FUNDED)
    
    ;; Transfer back to buyer
    (try! (as-contract (stx-transfer? total-amount tx-sender buyer)))
    
    ;; Update escrow state
    (map-set escrows
      { escrow-id: escrow-id }
      (merge escrow { state: STATE_REFUNDED })
    )
    
    (ok { escrow-id: escrow-id, refunded-to: buyer, amount: total-amount })
  )
)

;; ============================================
;; Admin Functions
;; ============================================

;; Set fee collector
(define-public (set-fee-collector (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set fee-collector new-collector)
    (ok new-collector)
  )
)

;; Pause/unpause contract
(define-public (set-paused (paused bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-paused paused)
    (ok paused)
  )
)

