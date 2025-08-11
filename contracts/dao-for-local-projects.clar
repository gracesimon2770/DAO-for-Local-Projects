(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_VOTING_ENDED (err u403))
(define-constant ERR_VOTING_ACTIVE (err u405))
(define-constant ERR_ALREADY_VOTED (err u406))
(define-constant ERR_NOT_MEMBER (err u407))
(define-constant ERR_CANNOT_DELEGATE_TO_SELF (err u408))
(define-constant ERR_ALREADY_DELEGATED (err u409))

(define-data-var next-proposal-id uint u1)
(define-data-var next-member-id uint u1)
(define-data-var treasury-balance uint u0)
(define-data-var voting-period uint u1440)
(define-data-var min-votes-required uint u3)

(define-map members 
  { member-id: uint }
  { 
    address: principal,
    joined-at: uint,
    voting-power: uint,
    is-active: bool,
    delegated-to: (optional principal),
    delegated-power: uint
  }
)

(define-map member-by-address
  { address: principal }
  { member-id: uint }
)

(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    funding-amount: uint,
    created-at: uint,
    voting-ends-at: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 20),
    executed: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-map project-updates
  { proposal-id: uint, update-id: uint }
  {
    message: (string-ascii 300),
    timestamp: uint,
    reporter: principal
  }
)

(define-map proposal-update-count
  { proposal-id: uint }
  { count: uint }
)

(define-public (join-dao)
  (let 
    (
      (caller tx-sender)
      (member-id (var-get next-member-id))
    )
    (asserts! (is-none (map-get? member-by-address { address: caller })) ERR_ALREADY_EXISTS)
    
    (map-set members 
      { member-id: member-id }
      {
        address: caller,
        joined-at: stacks-block-height,
        voting-power: u1,
        is-active: true,
        delegated-to: none,
        delegated-power: u0
      }
    )
    
    (map-set member-by-address
      { address: caller }
      { member-id: member-id }
    )
    
    (var-set next-member-id (+ member-id u1))
    (ok member-id)
  )
)

(define-public (propose-project (title (string-ascii 100)) (description (string-ascii 500)) (funding-amount uint))
  (let 
    (
      (caller tx-sender)
      (proposal-id (var-get next-proposal-id))
      (member-data (map-get? member-by-address { address: caller }))
    )
    (asserts! (is-some member-data) ERR_NOT_MEMBER)
    (asserts! (> funding-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= funding-amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        proposer: caller,
        funding-amount: funding-amount,
        created-at: stacks-block-height,
        voting-ends-at: (+ stacks-block-height (var-get voting-period)),
        votes-for: u0,
        votes-against: u0,
        status: "active",
        executed: false
      }
    )
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let 
    (
      (caller tx-sender)
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_NOT_FOUND))
      (member-data (unwrap! (map-get? member-by-address { address: caller }) ERR_NOT_MEMBER))
      (member-info (unwrap! (map-get? members { member-id: (get member-id member-data) }) ERR_NOT_FOUND))
      (base-power (get voting-power member-info))
      (delegated-power (get delegated-power member-info))
      (voting-power (+ base-power delegated-power))
    )
    (asserts! (get is-active member-info) ERR_NOT_AUTHORIZED)
    (asserts! (<= stacks-block-height (get voting-ends-at proposal)) ERR_VOTING_ENDED)
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: caller })) ERR_ALREADY_VOTED)
    
    (map-set votes
      { proposal-id: proposal-id, voter: caller }
      { vote: vote-for, voting-power: voting-power }
    )
    
    (if vote-for
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-for: (+ (get votes-for proposal) voting-power) })
      )
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-against: (+ (get votes-against proposal) voting-power) })
      )
    )
    
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let 
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_NOT_FOUND))
      (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
    )
    (asserts! (> stacks-block-height (get voting-ends-at proposal)) ERR_VOTING_ACTIVE)
    (asserts! (not (get executed proposal)) ERR_ALREADY_EXISTS)
    (asserts! (>= total-votes (var-get min-votes-required)) ERR_INVALID_AMOUNT)
    
    (if (> (get votes-for proposal) (get votes-against proposal))
      (begin
        (asserts! (>= (var-get treasury-balance) (get funding-amount proposal)) ERR_INSUFFICIENT_FUNDS)
        (var-set treasury-balance (- (var-get treasury-balance) (get funding-amount proposal)))
        (try! (as-contract (stx-transfer? (get funding-amount proposal) tx-sender (get proposer proposal))))
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal { status: "approved", executed: true })
        )
        (ok "approved")
      )
      (begin
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal { status: "rejected", executed: true })
        )
        (ok "rejected")
      )
    )
  )
)

(define-public (add-project-update (proposal-id uint) (message (string-ascii 300)))
  (let 
    (
      (caller tx-sender)
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_NOT_FOUND))
      (current-count (default-to u0 (get count (map-get? proposal-update-count { proposal-id: proposal-id }))))
      (update-id (+ current-count u1))
    )
    (asserts! (is-eq caller (get proposer proposal)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status proposal) "approved") ERR_NOT_AUTHORIZED)
    
    (map-set project-updates
      { proposal-id: proposal-id, update-id: update-id }
      {
        message: message,
        timestamp: stacks-block-height,
        reporter: caller
      }
    )
    
    (map-set proposal-update-count
      { proposal-id: proposal-id }
      { count: update-id }
    )
    
    (ok update-id)
  )
)

(define-public (fund-treasury)
  (let ((amount (stx-get-balance tx-sender)))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok amount)
  )
)

(define-public (set-voting-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> new-period u0) ERR_INVALID_AMOUNT)
    (var-set voting-period new-period)
    (ok new-period)
  )
)

(define-public (set-min-votes (min-votes uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> min-votes u0) ERR_INVALID_AMOUNT)
    (var-set min-votes-required min-votes)
    (ok min-votes)
  )
)

(define-public (delegate-voting-power (delegate-to principal))
  (let 
    (
      (caller tx-sender)
      (delegator-data (unwrap! (map-get? member-by-address { address: caller }) ERR_NOT_MEMBER))
      (delegator-info (unwrap! (map-get? members { member-id: (get member-id delegator-data) }) ERR_NOT_FOUND))
      (delegate-data (unwrap! (map-get? member-by-address { address: delegate-to }) ERR_NOT_MEMBER))
      (delegate-info (unwrap! (map-get? members { member-id: (get member-id delegate-data) }) ERR_NOT_FOUND))
      (delegator-power (get voting-power delegator-info))
    )
    (asserts! (not (is-eq caller delegate-to)) ERR_CANNOT_DELEGATE_TO_SELF)
    (asserts! (get is-active delegator-info) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active delegate-info) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (get delegated-to delegator-info)) ERR_ALREADY_DELEGATED)
    
    (map-set members
      { member-id: (get member-id delegator-data) }
      (merge delegator-info { delegated-to: (some delegate-to) })
    )
    
    (map-set members
      { member-id: (get member-id delegate-data) }
      (merge delegate-info { delegated-power: (+ (get delegated-power delegate-info) delegator-power) })
    )
    
    (ok true)
  )
)

(define-public (revoke-delegation)
  (let 
    (
      (caller tx-sender)
      (delegator-data (unwrap! (map-get? member-by-address { address: caller }) ERR_NOT_MEMBER))
      (delegator-info (unwrap! (map-get? members { member-id: (get member-id delegator-data) }) ERR_NOT_FOUND))
      (delegate-address (unwrap! (get delegated-to delegator-info) ERR_NOT_FOUND))
      (delegate-data (unwrap! (map-get? member-by-address { address: delegate-address }) ERR_NOT_MEMBER))
      (delegate-info (unwrap! (map-get? members { member-id: (get member-id delegate-data) }) ERR_NOT_FOUND))
      (delegator-power (get voting-power delegator-info))
    )
    (asserts! (get is-active delegator-info) ERR_NOT_AUTHORIZED)
    
    (map-set members
      { member-id: (get member-id delegator-data) }
      (merge delegator-info { delegated-to: none })
    )
    
    (map-set members
      { member-id: (get member-id delegate-data) }
      (merge delegate-info { delegated-power: (- (get delegated-power delegate-info) delegator-power) })
    )
    
    (ok true)
  )
)

(define-read-only (get-member (member-id uint))
  (map-get? members { member-id: member-id })
)

(define-read-only (get-member-by-address (address principal))
  (map-get? member-by-address { address: address })
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-project-update (proposal-id uint) (update-id uint))
  (map-get? project-updates { proposal-id: proposal-id, update-id: update-id })
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-voting-period)
  (var-get voting-period)
)

(define-read-only (get-min-votes-required)
  (var-get min-votes-required)
)

(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)

(define-read-only (get-next-member-id)
  (var-get next-member-id)
)

(define-read-only (get-delegation-info (address principal))
  (let 
    (
      (member-data (map-get? member-by-address { address: address }))
    )
    (match member-data
      member-info
        (let ((member-details (map-get? members { member-id: (get member-id member-info) })))
          (match member-details
            details (some { 
              delegated-to: (get delegated-to details),
              delegated-power: (get delegated-power details),
              effective-voting-power: (+ (get voting-power details) (get delegated-power details))
            })
            none
          )
        )
      none
    )
  )
)

(define-read-only (get-effective-voting-power (address principal))
  (let 
    (
      (member-data (map-get? member-by-address { address: address }))
    )
    (match member-data
      member-info
        (let ((member-details (map-get? members { member-id: (get member-id member-info) })))
          (match member-details
            details (some (+ (get voting-power details) (get delegated-power details)))
            none
          )
        )
      none
    )
  )
)
