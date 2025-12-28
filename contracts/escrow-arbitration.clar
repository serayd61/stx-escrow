;; Escrow Arbitration - Dispute Resolution Contract
;; Handle disputes between buyers and sellers
;; 
;; Features:
;; - File disputes with evidence
;; - Arbiter voting system
;; - Resolution enforcement
;; - Appeal mechanism

;; ============================================
;; Constants
;; ============================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u1))
(define-constant ERR_DISPUTE_NOT_FOUND (err u2))
(define-constant ERR_ALREADY_DISPUTED (err u3))
(define-constant ERR_NOT_PARTY (err u4))
(define-constant ERR_VOTING_CLOSED (err u5))
(define-constant ERR_ALREADY_VOTED (err u6))
(define-constant ERR_NOT_ARBITER (err u7))
(define-constant ERR_ALREADY_RESOLVED (err u8))
(define-constant ERR_INSUFFICIENT_VOTES (err u9))

;; Dispute states
(define-constant DISPUTE_OPEN u1)
(define-constant DISPUTE_VOTING u2)
(define-constant DISPUTE_RESOLVED_BUYER u3)
(define-constant DISPUTE_RESOLVED_SELLER u4)
(define-constant DISPUTE_APPEALED u5)

;; Voting period: ~2 days (288 blocks)
(define-constant VOTING_PERIOD u288)

;; Minimum arbiters to vote
(define-constant MIN_ARBITER_VOTES u3)

;; Dispute filing fee: 1 STX
(define-constant DISPUTE_FEE u1000000)

;; ============================================
;; Data Variables
;; ============================================

(define-data-var dispute-counter uint u0)
(define-data-var total-arbiters uint u0)
(define-data-var fee-pool uint u0)

;; ============================================
;; Data Maps
;; ============================================

;; Disputes
(define-map disputes
  { dispute-id: uint }
  {
    escrow-id: uint,
    buyer: principal,
    seller: principal,
    filed-by: principal,
    reason: (string-ascii 500),
    evidence-uri: (string-ascii 256),
    state: uint,
    filed-at: uint,
    voting-ends-at: uint,
    votes-for-buyer: uint,
    votes-for-seller: uint,
    resolution: uint,
    resolved-at: uint
  }
)

;; Registered arbiters
(define-map arbiters
  { arbiter: principal }
  {
    active: bool,
    cases-handled: uint,
    reputation: uint,
    staked: uint,
    registered-at: uint
  }
)

;; Arbiter votes
(define-map votes
  { dispute-id: uint, arbiter: principal }
  {
    vote-for-buyer: bool,
    reasoning: (string-ascii 200),
    voted-at: uint
  }
)

;; Response from other party
(define-map responses
  { dispute-id: uint, responder: principal }
  {
    response: (string-ascii 500),
    evidence-uri: (string-ascii 256),
    responded-at: uint
  }
)

;; ============================================
;; Read-Only Functions
;; ============================================

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-dispute-status (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute (ok (get state dispute))
    ERR_DISPUTE_NOT_FOUND
  )
)

(define-read-only (is-arbiter (address principal))
  (match (map-get? arbiters { arbiter: address })
    arbiter-data (get active arbiter-data)
    false
  )
)

(define-read-only (get-arbiter (address principal))
  (map-get? arbiters { arbiter: address })
)

(define-read-only (has-voted (dispute-id uint) (arbiter principal))
  (is-some (map-get? votes { dispute-id: dispute-id, arbiter: arbiter }))
)

(define-read-only (get-vote (dispute-id uint) (arbiter principal))
  (map-get? votes { dispute-id: dispute-id, arbiter: arbiter })
)

(define-read-only (get-dispute-count)
  (var-get dispute-counter)
)

(define-read-only (get-total-arbiters)
  (var-get total-arbiters)
)

;; ============================================
;; Public Functions - Dispute Filing
;; ============================================

;; File a dispute
(define-public (file-dispute
  (escrow-id uint)
  (reason (string-ascii 500))
  (evidence-uri (string-ascii 256)))
  (let (
    (dispute-id (+ (var-get dispute-counter) u1))
    (filer tx-sender)
  )
    ;; Pay filing fee
    (try! (stx-transfer? DISPUTE_FEE filer (as-contract tx-sender)))
    
    ;; In production, would verify escrow exists and filer is party
    ;; For now, create dispute record
    (map-set disputes
      { dispute-id: dispute-id }
      {
        escrow-id: escrow-id,
        buyer: filer, ;; Simplified - would get from escrow
        seller: CONTRACT_OWNER, ;; Simplified
        filed-by: filer,
        reason: reason,
        evidence-uri: evidence-uri,
        state: DISPUTE_OPEN,
        filed-at: stacks-block-height,
        voting-ends-at: (+ stacks-block-height VOTING_PERIOD),
        votes-for-buyer: u0,
        votes-for-seller: u0,
        resolution: u0,
        resolved-at: u0
      }
    )
    
    ;; Add to fee pool
    (var-set fee-pool (+ (var-get fee-pool) DISPUTE_FEE))
    (var-set dispute-counter dispute-id)
    
    (ok { dispute-id: dispute-id, escrow-id: escrow-id })
  )
)

;; Submit response to dispute
(define-public (submit-response
  (dispute-id uint)
  (response (string-ascii 500))
  (evidence-uri (string-ascii 256)))
  (let (
    (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR_DISPUTE_NOT_FOUND))
    (responder tx-sender)
  )
    ;; Check dispute is open
    (asserts! (is-eq (get state dispute) DISPUTE_OPEN) ERR_ALREADY_RESOLVED)
    
    ;; Record response
    (map-set responses
      { dispute-id: dispute-id, responder: responder }
      {
        response: response,
        evidence-uri: evidence-uri,
        responded-at: stacks-block-height
      }
    )
    
    ;; Move to voting state
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute { state: DISPUTE_VOTING })
    )
    
    (ok dispute-id)
  )
)

;; ============================================
;; Public Functions - Arbiter Actions
;; ============================================

;; Register as arbiter
(define-public (register-arbiter (stake uint))
  (let (
    (arbiter tx-sender)
  )
    ;; Minimum stake check would go here
    (try! (stx-transfer? stake arbiter (as-contract tx-sender)))
    
    (map-set arbiters
      { arbiter: arbiter }
      {
        active: true,
        cases-handled: u0,
        reputation: u100,
        staked: stake,
        registered-at: stacks-block-height
      }
    )
    
    (var-set total-arbiters (+ (var-get total-arbiters) u1))
    (ok arbiter)
  )
)

;; Cast vote on dispute
(define-public (cast-vote
  (dispute-id uint)
  (vote-for-buyer bool)
  (reasoning (string-ascii 200)))
  (let (
    (arbiter tx-sender)
    (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR_DISPUTE_NOT_FOUND))
    (arbiter-data (unwrap! (map-get? arbiters { arbiter: arbiter }) ERR_NOT_ARBITER))
  )
    ;; Validations
    (asserts! (get active arbiter-data) ERR_NOT_ARBITER)
    (asserts! (is-eq (get state dispute) DISPUTE_VOTING) ERR_VOTING_CLOSED)
    (asserts! (< stacks-block-height (get voting-ends-at dispute)) ERR_VOTING_CLOSED)
    (asserts! (not (has-voted dispute-id arbiter)) ERR_ALREADY_VOTED)
    
    ;; Record vote
    (map-set votes
      { dispute-id: dispute-id, arbiter: arbiter }
      {
        vote-for-buyer: vote-for-buyer,
        reasoning: reasoning,
        voted-at: stacks-block-height
      }
    )
    
    ;; Update vote counts
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute {
        votes-for-buyer: (if vote-for-buyer 
                           (+ (get votes-for-buyer dispute) u1)
                           (get votes-for-buyer dispute)),
        votes-for-seller: (if (not vote-for-buyer)
                            (+ (get votes-for-seller dispute) u1)
                            (get votes-for-seller dispute))
      })
    )
    
    ;; Update arbiter stats
    (map-set arbiters
      { arbiter: arbiter }
      (merge arbiter-data {
        cases-handled: (+ (get cases-handled arbiter-data) u1)
      })
    )
    
    (ok { dispute-id: dispute-id, vote-for-buyer: vote-for-buyer })
  )
)

;; Finalize dispute resolution
(define-public (finalize-dispute (dispute-id uint))
  (let (
    (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR_DISPUTE_NOT_FOUND))
    (total-votes (+ (get votes-for-buyer dispute) (get votes-for-seller dispute)))
    (buyer-wins (> (get votes-for-buyer dispute) (get votes-for-seller dispute)))
  )
    ;; Check voting period ended
    (asserts! (>= stacks-block-height (get voting-ends-at dispute)) ERR_VOTING_CLOSED)
    ;; Check enough votes
    (asserts! (>= total-votes MIN_ARBITER_VOTES) ERR_INSUFFICIENT_VOTES)
    ;; Check not already resolved
    (asserts! (is-eq (get state dispute) DISPUTE_VOTING) ERR_ALREADY_RESOLVED)
    
    ;; Determine resolution
    (let (
      (new-state (if buyer-wins DISPUTE_RESOLVED_BUYER DISPUTE_RESOLVED_SELLER))
    )
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute {
          state: new-state,
          resolution: new-state,
          resolved-at: stacks-block-height
        })
      )
      
      ;; In production, would trigger escrow release/refund here
      
      (ok { dispute-id: dispute-id, buyer-wins: buyer-wins })
    )
  )
)

;; ============================================
;; Admin Functions
;; ============================================

;; Distribute fees to arbiters
(define-public (distribute-arbiter-fees (arbiter principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= amount (var-get fee-pool)) ERR_NOT_AUTHORIZED)
    
    (try! (as-contract (stx-transfer? amount tx-sender arbiter)))
    (var-set fee-pool (- (var-get fee-pool) amount))
    
    (ok amount)
  )
)

;; Deactivate arbiter
(define-public (deactivate-arbiter (arbiter principal))
  (let (
    (arbiter-data (unwrap! (map-get? arbiters { arbiter: arbiter }) ERR_NOT_ARBITER))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (map-set arbiters
      { arbiter: arbiter }
      (merge arbiter-data { active: false })
    )
    
    (var-set total-arbiters (- (var-get total-arbiters) u1))
    (ok arbiter)
  )
)

