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
(define-constant ERR_MILESTONE_NOT_FOUND (err u410))
(define-constant ERR_MILESTONE_ALREADY_COMPLETED (err u411))
(define-constant ERR_INSUFFICIENT_MILESTONE_VOTES (err u412))
(define-constant ERR_PAUSED (err u413))

(define-data-var next-proposal-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var next-member-id uint u1)
(define-data-var treasury-balance uint u0)
(define-data-var voting-period uint u1440)
(define-data-var min-votes-required uint u3)
(define-data-var reputation-enabled bool true)
(define-data-var contract-paused bool false)

(define-map operators
  { address: principal }
  { active: bool }
)

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

(define-private (is-admin (caller principal))
  (let 
    (
      (owner (is-eq caller CONTRACT_OWNER))
      (op-data (map-get? operators { address: caller }))
    )
    (match op-data
      data (or owner (get active data))
      owner
    )
  )
)

(define-read-only (is-operator (address principal))
  (match (map-get? operators { address: address })
    data (get active data)
    false
  )
)

(define-public (grant-operator (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set operators { address: address } { active: true })
    (ok true)
  )
)

(define-public (revoke-operator (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set operators { address: address } { active: false })
    (ok true)
  )
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

(define-map milestones
  { milestone-id: uint }
  {
    proposal-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 300),
    funding-amount: uint,
    completion-votes: uint,
    required-votes: uint,
    completed: bool,
    created-at: uint
  }
)

(define-map milestone-completion-votes
  { milestone-id: uint, voter: principal }
  { voted: bool }
)

(define-map proposal-milestones
  { proposal-id: uint }
  { milestone-count: uint, completed-count: uint, total-funding: uint }
)

(define-map member-reputation
  { address: principal }
  {
    reputation-score: uint,
    proposals-created: uint,
    proposals-approved: uint,
    votes-cast: uint,
    milestones-completed: uint,
    last-updated: uint
  }
)

(define-public (join-dao)
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
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
      
      (map-set member-reputation
        { address: caller }
        {
          reputation-score: u0,
          proposals-created: u0,
          proposals-approved: u0,
          votes-cast: u0,
          milestones-completed: u0,
          last-updated: stacks-block-height
        }
      )
      
      (var-set next-member-id (+ member-id u1))
      (ok member-id)
    )
  )
)

(define-public (propose-project (title (string-ascii 100)) (description (string-ascii 500)) (funding-amount uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
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
      
      (unwrap! (award-reputation-for-proposal caller) (ok proposal-id))
      
      (var-set next-proposal-id (+ proposal-id u1))
      (ok proposal-id)
    )
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
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
      
      (unwrap! (award-reputation-for-voting caller) (ok true))
      
      (ok true)
    )
  )
)

(define-public (execute-proposal (proposal-id uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
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
          (unwrap! (award-reputation-for-approval (get proposer proposal)) (ok "approved"))
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
)

(define-public (add-project-update (proposal-id uint) (message (string-ascii 300)))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
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
)

(define-public (fund-treasury)
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (let ((amount (stx-get-balance tx-sender)))
      (asserts! (> amount u0) ERR_INVALID_AMOUNT)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (var-set treasury-balance (+ (var-get treasury-balance) amount))
      (ok amount)
    )
  )
)

(define-public (set-voting-period (new-period uint))
  (begin
    (let ((caller tx-sender))
      (asserts! (is-admin caller) ERR_NOT_AUTHORIZED)
      (asserts! (> new-period u0) ERR_INVALID_AMOUNT)
      (var-set voting-period new-period)
      (ok new-period)
    )
  )
)

(define-public (set-min-votes (min-votes uint))
  (begin
    (let ((caller tx-sender))
      (asserts! (is-admin caller) ERR_NOT_AUTHORIZED)
      (asserts! (> min-votes u0) ERR_INVALID_AMOUNT)
      (var-set min-votes-required min-votes)
      (ok min-votes)
    )
  )
)

(define-public (delegate-voting-power (delegate-to principal))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
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
)

(define-public (revoke-delegation)
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
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
)

(define-public (create-milestone (proposal-id uint) (title (string-ascii 100)) (description (string-ascii 300)) (funding-amount uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (let 
      (
        (caller tx-sender)
        (milestone-id (var-get next-milestone-id))
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_NOT_FOUND))
        (required-votes (var-get min-votes-required))
      )
      (asserts! (is-eq caller (get proposer proposal)) ERR_NOT_AUTHORIZED)
      (asserts! (is-eq (get status proposal) "approved") ERR_NOT_AUTHORIZED)
      (asserts! (> funding-amount u0) ERR_INVALID_AMOUNT)
      
      (map-set milestones
        { milestone-id: milestone-id }
        {
          proposal-id: proposal-id,
          title: title,
          description: description,
          funding-amount: funding-amount,
          completion-votes: u0,
          required-votes: required-votes,
          completed: false,
          created-at: stacks-block-height
        }
      )
      
      (let ((milestone-info (default-to { milestone-count: u0, completed-count: u0, total-funding: u0 } 
                                        (map-get? proposal-milestones { proposal-id: proposal-id }))))
        (map-set proposal-milestones
          { proposal-id: proposal-id }
          {
            milestone-count: (+ (get milestone-count milestone-info) u1),
            completed-count: (get completed-count milestone-info),
            total-funding: (+ (get total-funding milestone-info) funding-amount)
          }
        )
      )
      
      (var-set next-milestone-id (+ milestone-id u1))
      (ok milestone-id)
    )
  )
)

(define-public (vote-milestone-completion (milestone-id uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (let 
      (
        (caller tx-sender)
        (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
        (member-data (unwrap! (map-get? member-by-address { address: caller }) ERR_NOT_MEMBER))
        (member-info (unwrap! (map-get? members { member-id: (get member-id member-data) }) ERR_NOT_FOUND))
      )
      (asserts! (get is-active member-info) ERR_NOT_AUTHORIZED)
      (asserts! (not (get completed milestone)) ERR_MILESTONE_ALREADY_COMPLETED)
      (asserts! (is-none (map-get? milestone-completion-votes { milestone-id: milestone-id, voter: caller })) ERR_ALREADY_VOTED)
      
      (map-set milestone-completion-votes
        { milestone-id: milestone-id, voter: caller }
        { voted: true }
      )
      
      (let ((new-votes (+ (get completion-votes milestone) u1)))
        (map-set milestones
          { milestone-id: milestone-id }
          (merge milestone { completion-votes: new-votes })
        )
        
        (if (>= new-votes (get required-votes milestone))
          (complete-milestone-funding milestone-id)
          (ok false)
        )
      )
    )
  )
)

(define-private (award-reputation-for-proposal (member principal))
  (let 
    (
      (rep-data (default-to 
        { reputation-score: u0, proposals-created: u0, proposals-approved: u0, votes-cast: u0, milestones-completed: u0, last-updated: u0 }
        (map-get? member-reputation { address: member })))
    )
    (if (var-get reputation-enabled)
      (begin
        (map-set member-reputation
          { address: member }
          (merge rep-data { 
            proposals-created: (+ (get proposals-created rep-data) u1),
            reputation-score: (+ (get reputation-score rep-data) u5),
            last-updated: stacks-block-height
          })
        )
        (ok true)
      )
      (ok true)
    )
  )
)

(define-private (award-reputation-for-approval (member principal))
  (let 
    (
      (rep-data (default-to 
        { reputation-score: u0, proposals-created: u0, proposals-approved: u0, votes-cast: u0, milestones-completed: u0, last-updated: u0 }
        (map-get? member-reputation { address: member })))
    )
    (if (var-get reputation-enabled)
      (begin
        (map-set member-reputation
          { address: member }
          (merge rep-data { 
            proposals-approved: (+ (get proposals-approved rep-data) u1),
            reputation-score: (+ (get reputation-score rep-data) u20),
            last-updated: stacks-block-height
          })
        )
        (ok true)
      )
      (ok true)
    )
  )
)

(define-private (award-reputation-for-voting (member principal))
  (let 
    (
      (rep-data (default-to 
        { reputation-score: u0, proposals-created: u0, proposals-approved: u0, votes-cast: u0, milestones-completed: u0, last-updated: u0 }
        (map-get? member-reputation { address: member })))
    )
    (if (var-get reputation-enabled)
      (begin
        (map-set member-reputation
          { address: member }
          (merge rep-data { 
            votes-cast: (+ (get votes-cast rep-data) u1),
            reputation-score: (+ (get reputation-score rep-data) u1),
            last-updated: stacks-block-height
          })
        )
        (ok true)
      )
      (ok true)
    )
  )
)

(define-private (award-reputation-for-milestone (member principal))
  (let 
    (
      (rep-data (default-to 
        { reputation-score: u0, proposals-created: u0, proposals-approved: u0, votes-cast: u0, milestones-completed: u0, last-updated: u0 }
        (map-get? member-reputation { address: member })))
    )
    (if (var-get reputation-enabled)
      (begin
        (map-set member-reputation
          { address: member }
          (merge rep-data { 
            milestones-completed: (+ (get milestones-completed rep-data) u1),
            reputation-score: (+ (get reputation-score rep-data) u15),
            last-updated: stacks-block-height
          })
        )
        (ok true)
      )
      (ok true)
    )
  )
)

(define-private (complete-milestone-funding (milestone-id uint))
  (let 
    (
      (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
      (proposal (unwrap! (map-get? proposals { proposal-id: (get proposal-id milestone) }) ERR_NOT_FOUND))
      (funding-amount (get funding-amount milestone))
    )
    (asserts! (>= (var-get treasury-balance) funding-amount) ERR_INSUFFICIENT_FUNDS)
    
    (var-set treasury-balance (- (var-get treasury-balance) funding-amount))
    (try! (as-contract (stx-transfer? funding-amount tx-sender (get proposer proposal))))
    
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone { completed: true })
    )
    
    (let ((milestone-info (unwrap! (map-get? proposal-milestones { proposal-id: (get proposal-id milestone) }) ERR_NOT_FOUND)))
      (map-set proposal-milestones
        { proposal-id: (get proposal-id milestone) }
        (merge milestone-info { completed-count: (+ (get completed-count milestone-info) u1) })
      )
    )
    
    (unwrap! (award-reputation-for-milestone (get proposer proposal)) (ok true))
    
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

(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (get-proposal-milestone-info (proposal-id uint))
  (map-get? proposal-milestones { proposal-id: proposal-id })
)

(define-read-only (get-milestone-completion-vote (milestone-id uint) (voter principal))
  (map-get? milestone-completion-votes { milestone-id: milestone-id, voter: voter })
)

(define-read-only (get-next-milestone-id)
  (var-get next-milestone-id)
)

(define-read-only (get-member-reputation (address principal))
  (map-get? member-reputation { address: address })
)

(define-read-only (get-reputation-score (address principal))
  (match (map-get? member-reputation { address: address })
    rep-data (some (get reputation-score rep-data))
    none
  )
)

(define-read-only (is-reputation-enabled)
  (var-get reputation-enabled)
)

(define-read-only (is-paused)
  (var-get contract-paused)
)

(define-public (pause-contract)
  (begin
    (let ((caller tx-sender))
      (asserts! (is-admin caller) ERR_NOT_AUTHORIZED)
      (var-set contract-paused true)
      (ok true)
    )
  )
)

(define-public (resume-contract)
  (begin
    (let ((caller tx-sender))
      (asserts! (is-admin caller) ERR_NOT_AUTHORIZED)
      (var-set contract-paused false)
      (ok true)
    )
  )
)
