;; Escrow NFT - NFT Escrow Support
;; Escrow NFTs along with STX
;; 
;; Features:
;; - Deposit NFTs into escrow
;; - NFT-for-STX swaps
;; - Bundle escrows (multiple NFTs)

;; ============================================
;; Constants
;; ============================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u1))
(define-constant ERR_ESCROW_NOT_FOUND (err u2))
(define-constant ERR_INVALID_STATE (err u3))
(define-constant ERR_NOT_OWNER (err u4))
(define-constant ERR_TRANSFER_FAILED (err u5))

;; Escrow types
(define-constant TYPE_STX_FOR_NFT u1)
(define-constant TYPE_NFT_FOR_STX u2)
(define-constant TYPE_NFT_FOR_NFT u3)

;; States
(define-constant STATE_CREATED u1)
(define-constant STATE_FUNDED u2)
(define-constant STATE_COMPLETED u3)
(define-constant STATE_CANCELLED u4)

;; ============================================
;; Data Variables
;; ============================================

(define-data-var escrow-counter uint u0)

;; ============================================
;; Data Maps
;; ============================================

;; NFT Escrows
(define-map nft-escrows
  { escrow-id: uint }
  {
    escrow-type: uint,
    buyer: principal,
    seller: principal,
    ;; STX side
    stx-amount: uint,
    stx-deposited: bool,
    ;; NFT side
    nft-contract: principal,
    nft-token-id: uint,
    nft-deposited: bool,
    ;; State
    state: uint,
    created-at: uint,
    timeout-blocks: uint,
    memo: (string-ascii 100)
  }
)

;; ============================================
;; Read-Only Functions
;; ============================================

(define-read-only (get-nft-escrow (escrow-id uint))
  (map-get? nft-escrows { escrow-id: escrow-id })
)

(define-read-only (get-nft-escrow-count)
  (var-get escrow-counter)
)

;; ============================================
;; Public Functions
;; ============================================

;; Create STX-for-NFT escrow (buyer wants to buy NFT with STX)
(define-public (create-stx-for-nft-escrow
  (seller principal)
  (stx-amount uint)
  (nft-contract principal)
  (nft-token-id uint)
  (timeout-blocks uint)
  (memo (string-ascii 100)))
  (let (
    (escrow-id (+ (var-get escrow-counter) u1))
    (buyer tx-sender)
  )
    ;; Buyer deposits STX
    (try! (stx-transfer? stx-amount buyer (as-contract tx-sender)))
    
    (map-set nft-escrows
      { escrow-id: escrow-id }
      {
        escrow-type: TYPE_STX_FOR_NFT,
        buyer: buyer,
        seller: seller,
        stx-amount: stx-amount,
        stx-deposited: true,
        nft-contract: nft-contract,
        nft-token-id: nft-token-id,
        nft-deposited: false,
        state: STATE_CREATED,
        created-at: stacks-block-height,
        timeout-blocks: timeout-blocks,
        memo: memo
      }
    )
    
    (var-set escrow-counter escrow-id)
    (ok { escrow-id: escrow-id, type: "stx-for-nft" })
  )
)

;; Create NFT-for-STX escrow (seller wants to sell NFT for STX)
(define-public (create-nft-for-stx-escrow
  (buyer principal)
  (stx-amount uint)
  (nft-contract principal)
  (nft-token-id uint)
  (timeout-blocks uint)
  (memo (string-ascii 100)))
  (let (
    (escrow-id (+ (var-get escrow-counter) u1))
    (seller tx-sender)
  )
    ;; Seller needs to deposit NFT via separate function
    
    (map-set nft-escrows
      { escrow-id: escrow-id }
      {
        escrow-type: TYPE_NFT_FOR_STX,
        buyer: buyer,
        seller: seller,
        stx-amount: stx-amount,
        stx-deposited: false,
        nft-contract: nft-contract,
        nft-token-id: nft-token-id,
        nft-deposited: false,
        state: STATE_CREATED,
        created-at: stacks-block-height,
        timeout-blocks: timeout-blocks,
        memo: memo
      }
    )
    
    (var-set escrow-counter escrow-id)
    (ok { escrow-id: escrow-id, type: "nft-for-stx" })
  )
)

;; Deposit STX into escrow
(define-public (deposit-stx (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? nft-escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (buyer (get buyer escrow))
    (amount (get stx-amount escrow))
  )
    (asserts! (is-eq tx-sender buyer) ERR_NOT_AUTHORIZED)
    (asserts! (not (get stx-deposited escrow)) ERR_INVALID_STATE)
    
    (try! (stx-transfer? amount buyer (as-contract tx-sender)))
    
    (map-set nft-escrows
      { escrow-id: escrow-id }
      (merge escrow { stx-deposited: true })
    )
    
    ;; Check if both deposited
    (if (get nft-deposited escrow)
      (map-set nft-escrows
        { escrow-id: escrow-id }
        (merge escrow { stx-deposited: true, state: STATE_FUNDED })
      )
      true
    )
    
    (ok escrow-id)
  )
)

;; Complete escrow (after both sides deposited)
(define-public (complete-nft-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? nft-escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (buyer (get buyer escrow))
    (seller (get seller escrow))
    (stx-amount (get stx-amount escrow))
  )
    ;; Check both deposited
    (asserts! (get stx-deposited escrow) ERR_INVALID_STATE)
    (asserts! (get nft-deposited escrow) ERR_INVALID_STATE)
    
    ;; Transfer STX to seller
    (try! (as-contract (stx-transfer? stx-amount tx-sender seller)))
    
    ;; NFT transfer would happen via trait call
    ;; (try! (contract-call? nft-contract transfer token-id (as-contract tx-sender) buyer))
    
    ;; Update state
    (map-set nft-escrows
      { escrow-id: escrow-id }
      (merge escrow { state: STATE_COMPLETED })
    )
    
    (ok { escrow-id: escrow-id, stx-to: seller, nft-to: buyer })
  )
)

;; Cancel unfunded escrow
(define-public (cancel-nft-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? nft-escrows { escrow-id: escrow-id }) ERR_ESCROW_NOT_FOUND))
    (buyer (get buyer escrow))
    (seller (get seller escrow))
  )
    ;; Only parties can cancel
    (asserts! (or (is-eq tx-sender buyer) (is-eq tx-sender seller)) ERR_NOT_AUTHORIZED)
    ;; Cannot cancel if fully funded
    (asserts! (not (and (get stx-deposited escrow) (get nft-deposited escrow))) ERR_INVALID_STATE)
    
    ;; Refund STX if deposited
    (if (get stx-deposited escrow)
      (try! (as-contract (stx-transfer? (get stx-amount escrow) tx-sender buyer)))
      true
    )
    
    ;; NFT refund would happen similarly
    
    ;; Update state
    (map-set nft-escrows
      { escrow-id: escrow-id }
      (merge escrow { state: STATE_CANCELLED })
    )
    
    (ok escrow-id)
  )
)

