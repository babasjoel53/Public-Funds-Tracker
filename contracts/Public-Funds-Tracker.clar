(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-not-found (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-project-inactive (err u106))

(define-data-var treasury-balance uint u0)
(define-data-var next-project-id uint u1)
(define-data-var next-disbursement-id uint u1)

(define-map projects
    uint
    {
        name: (string-ascii 100),
        description: (string-ascii 500),
        allocated-amount: uint,
        spent-amount: uint,
        created-at: uint,
        created-by: principal,
        status: (string-ascii 20),
    }
)

(define-map disbursements
    uint
    {
        project-id: uint,
        amount: uint,
        recipient: principal,
        purpose: (string-ascii 200),
        timestamp: uint,
        approved-by: principal,
    }
)

(define-map project-managers
    uint
    principal
)
(define-map authorized-auditors
    principal
    bool
)

(define-public (initialize-treasury (initial-amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> initial-amount u0) err-invalid-amount)
        (var-set treasury-balance initial-amount)
        (ok true)
    )
)

(define-public (deposit-funds (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

(define-public (create-project
        (name (string-ascii 100))
        (description (string-ascii 500))
        (allocated-amount uint)
        (manager principal)
    )
    (let (
            (project-id (var-get next-project-id))
            (current-treasury (var-get treasury-balance))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> allocated-amount u0) err-invalid-amount)
        (asserts! (>= current-treasury allocated-amount) err-insufficient-funds)
        (asserts! (is-none (map-get? projects project-id)) err-already-exists)

        (map-set projects project-id {
            name: name,
            description: description,
            allocated-amount: allocated-amount,
            spent-amount: u0,
            created-at: stacks-block-height,
            created-by: tx-sender,
            status: "active",
        })

        (map-set project-managers project-id manager)
        (var-set treasury-balance (- current-treasury allocated-amount))
        (var-set next-project-id (+ project-id u1))
        (ok project-id)
    )
)

(define-public (approve-disbursement
        (project-id uint)
        (amount uint)
        (recipient principal)
        (purpose (string-ascii 200))
    )
    (let (
            (project-data (unwrap! (map-get? projects project-id) err-not-found))
            (manager (unwrap! (map-get? project-managers project-id) err-not-found))
            (disbursement-id (var-get next-disbursement-id))
            (new-spent (+ (get spent-amount project-data) amount))
        )
        (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender manager))
            err-unauthorized
        )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (<= new-spent (get allocated-amount project-data))
            err-insufficient-funds
        )
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)

        (map-set disbursements disbursement-id {
            project-id: project-id,
            amount: amount,
            recipient: recipient,
            purpose: purpose,
            timestamp: stacks-block-height,
            approved-by: tx-sender,
        })

        (map-set projects project-id
            (merge project-data { spent-amount: new-spent })
        )

        (var-set next-disbursement-id (+ disbursement-id u1))
        (ok disbursement-id)
    )
)

(define-public (close-project (project-id uint))
    (let (
            (project-data (unwrap! (map-get? projects project-id) err-not-found))
            (remaining-funds (- (get allocated-amount project-data)
                (get spent-amount project-data)
            ))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)

        (map-set projects project-id (merge project-data { status: "closed" }))

        (var-set treasury-balance (+ (var-get treasury-balance) remaining-funds))
        (ok remaining-funds)
    )
)

(define-public (authorize-auditor (auditor principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set authorized-auditors auditor true)
        (ok true)
    )
)

(define-public (revoke-auditor (auditor principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-delete authorized-auditors auditor)
        (ok true)
    )
)

(define-public (emergency-pause-project (project-id uint))
    (let ((project-data (unwrap! (map-get? projects project-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set projects project-id (merge project-data { status: "paused" }))
        (ok true)
    )
)

(define-public (resume-project (project-id uint))
    (let ((project-data (unwrap! (map-get? projects project-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status project-data) "paused") err-project-inactive)
        (map-set projects project-id (merge project-data { status: "active" }))
        (ok true)
    )
)

(define-read-only (get-treasury-balance)
    (var-get treasury-balance)
)

(define-read-only (get-project (project-id uint))
    (map-get? projects project-id)
)

(define-read-only (get-project-manager (project-id uint))
    (map-get? project-managers project-id)
)

(define-read-only (get-disbursement (disbursement-id uint))
    (map-get? disbursements disbursement-id)
)

(define-read-only (get-project-utilization (project-id uint))
    (match (map-get? projects project-id)
        project-data (let (
                (allocated (get allocated-amount project-data))
                (spent (get spent-amount project-data))
            )
            (if (> allocated u0)
                (some (* (/ spent allocated) u100))
                none
            )
        )
        none
    )
)

(define-read-only (get-remaining-funds (project-id uint))
    (match (map-get? projects project-id)
        project-data (some (- (get allocated-amount project-data) (get spent-amount project-data)))
        none
    )
)

(define-read-only (is-authorized-auditor (auditor principal))
    (default-to false (map-get? authorized-auditors auditor))
)

(define-read-only (get-total-allocated-funds)
    (fold calculate-total-allocated
        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19
            u20)
        u0
    )
)

(define-read-only (get-total-spent-funds)
    (fold calculate-total-spent
        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19
            u20)
        u0
    )
)

(define-private (calculate-total-allocated
        (project-id uint)
        (current-total uint)
    )
    (match (map-get? projects project-id)
        project-data (+ current-total (get allocated-amount project-data))
        current-total
    )
)

(define-private (calculate-total-spent
        (project-id uint)
        (current-total uint)
    )
    (match (map-get? projects project-id)
        project-data (+ current-total (get spent-amount project-data))
        current-total
    )
)

(define-read-only (get-project-count)
    (- (var-get next-project-id) u1)
)

(define-read-only (get-disbursement-count)
    (- (var-get next-disbursement-id) u1)
)

(define-read-only (get-contract-owner)
    contract-owner
)
