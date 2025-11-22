(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-not-found (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-project-inactive (err u106))
(define-constant err-milestone-not-found (err u107))
(define-constant err-milestone-already-completed (err u108))
(define-constant err-milestone-pending (err u109))
(define-constant err-invalid-category (err u110))
(define-constant err-expenditure-not-found (err u111))
(define-constant err-category-limit-exceeded (err u112))
(define-constant err-invalid-rating (err u113))
(define-constant err-rating-exists (err u114))
(define-constant err-feedback-too-long (err u115))
(define-constant err-invalid-feedback-category (err u116))
(define-constant err-project-not-found (err u117))

(define-data-var treasury-balance uint u0)
(define-data-var next-project-id uint u1)
(define-data-var next-disbursement-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var next-expenditure-id uint u1)
(define-data-var next-feedback-id uint u1)

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

(define-map project-milestones
    uint
    {
        project-id: uint,
        description: (string-ascii 300),
        fund-percentage: uint,
        target-date: uint,
        completion-date: (optional uint),
        status: (string-ascii 20),
        created-by: principal,
        verified-by: (optional principal),
    }
)

(define-map expenditure-reports
    uint
    {
        project-id: uint,
        disbursement-id: uint,
        category: (string-ascii 50),
        amount: uint,
        description: (string-ascii 300),
        vendor: (optional principal),
        invoice-reference: (string-ascii 100),
        reported-by: principal,
        timestamp: uint,
        verified: bool,
        verified-by: (optional principal),
    }
)

(define-map project-category-budgets
    {
        project-id: uint,
        category: (string-ascii 50),
    }
    {
        allocated-amount: uint,
        spent-amount: uint,
        limit-percentage: uint,
    }
)

;; Public Engagement System Data Structures

;; Store project ratings: (project-id, citizen) -> {rating, comment, timestamp}
(define-map project-ratings
    {
        project-id: uint,
        citizen: principal,
    }
    {
        rating: uint,
        comment: (string-utf8 500),
        timestamp: uint,
    }
)

;; Store public feedback: feedback-id -> {project-id, citizen, text, category, timestamp}
(define-map public-feedback
    uint
    {
        project-id: uint,
        citizen: principal,
        feedback-text: (string-utf8 1000),
        category: (string-ascii 50),
        timestamp: uint,
    }
)

;; Track citizen engagement: citizen -> {ratings-count, feedback-count, last-activity}
(define-map citizen-engagement
    principal
    {
        ratings-count: uint,
        feedback-count: uint,
        last-activity: uint,
    }
)

;; Counter for feedback entries per project
(define-map project-feedback-counter uint uint)

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

(define-public (create-milestone
        (project-id uint)
        (description (string-ascii 300))
        (fund-percentage uint)
        (target-date uint)
    )
    (let ((milestone-id (var-get next-milestone-id)))
        (asserts! (is-some (map-get? projects project-id)) err-not-found)
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> fund-percentage u0) err-invalid-amount)
        (asserts! (<= fund-percentage u100) err-invalid-amount)
        (asserts! (> target-date stacks-block-height) err-invalid-amount)

        (map-set project-milestones milestone-id {
            project-id: project-id,
            description: description,
            fund-percentage: fund-percentage,
            target-date: target-date,
            completion-date: none,
            status: "pending",
            created-by: tx-sender,
            verified-by: none,
        })

        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (complete-milestone
        (milestone-id uint)
        (verification-note (string-ascii 200))
    )
    (let (
            (milestone-data (unwrap! (map-get? project-milestones milestone-id)
                err-milestone-not-found
            ))
            (project-data (unwrap! (map-get? projects (get project-id milestone-data))
                err-not-found
            ))
            (manager (unwrap! (map-get? project-managers (get project-id milestone-data))
                err-not-found
            ))
        )
        (asserts!
            (or
                (is-eq tx-sender contract-owner)
                (is-eq tx-sender manager)
                (is-authorized-auditor tx-sender)
            )
            err-unauthorized
        )
        (asserts! (is-eq (get status milestone-data) "pending")
            err-milestone-already-completed
        )
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)

        (map-set project-milestones milestone-id
            (merge milestone-data {
                completion-date: (some stacks-block-height),
                status: "completed",
                verified-by: (some tx-sender),
            })
        )
        (ok true)
    )
)

(define-public (release-milestone-funds (milestone-id uint))
    (let (
            (milestone-data (unwrap! (map-get? project-milestones milestone-id)
                err-milestone-not-found
            ))
            (project-data (unwrap! (map-get? projects (get project-id milestone-data))
                err-not-found
            ))
            (release-amount (/
                (* (get allocated-amount project-data)
                    (get fund-percentage milestone-data)
                )
                u100
            ))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status milestone-data) "completed")
            err-milestone-pending
        )
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)

        (let ((disbursement-id (var-get next-disbursement-id)))
            (map-set disbursements disbursement-id {
                project-id: (get project-id milestone-data),
                amount: release-amount,
                recipient: (unwrap!
                    (map-get? project-managers (get project-id milestone-data))
                    err-not-found
                ),
                purpose: "milestone-completion",
                timestamp: stacks-block-height,
                approved-by: tx-sender,
            })

            (map-set projects (get project-id milestone-data)
                (merge project-data { spent-amount: (+ (get spent-amount project-data) release-amount) })
            )

            (var-set next-disbursement-id (+ disbursement-id u1))
            (ok disbursement-id)
        )
    )
)

(define-public (set-category-budget
        (project-id uint)
        (category (string-ascii 50))
        (allocated-amount uint)
        (limit-percentage uint)
    )
    (begin
        (asserts! (is-some (map-get? projects project-id)) err-not-found)
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> allocated-amount u0) err-invalid-amount)
        (asserts! (<= limit-percentage u100) err-invalid-amount)
        (asserts! (is-valid-category category) err-invalid-category)

        (map-set project-category-budgets {
            project-id: project-id,
            category: category,
        } {
            allocated-amount: allocated-amount,
            spent-amount: u0,
            limit-percentage: limit-percentage,
        })
        (ok true)
    )
)

(define-public (submit-expenditure-report
        (project-id uint)
        (disbursement-id uint)
        (category (string-ascii 50))
        (amount uint)
        (description (string-ascii 300))
        (vendor (optional principal))
        (invoice-reference (string-ascii 100))
    )
    (let (
            (expenditure-id (var-get next-expenditure-id))
            (project-data (unwrap! (map-get? projects project-id) err-not-found))
            (disbursement-data (unwrap! (map-get? disbursements disbursement-id) err-not-found))
            (manager (unwrap! (map-get? project-managers project-id) err-not-found))
            (category-budget (map-get? project-category-budgets {
                project-id: project-id,
                category: category,
            }))
        )
        (asserts!
            (or
                (is-eq tx-sender contract-owner)
                (is-eq tx-sender manager)
            )
            err-unauthorized
        )
        (asserts! (is-eq (get project-id disbursement-data) project-id)
            err-not-found
        )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (is-valid-category category) err-invalid-category)
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)

        (match category-budget
            budget-data (let ((new-spent (+ (get spent-amount budget-data) amount)))
                (asserts! (<= new-spent (get allocated-amount budget-data))
                    err-category-limit-exceeded
                )
                (map-set project-category-budgets {
                    project-id: project-id,
                    category: category,
                }
                    (merge budget-data { spent-amount: new-spent })
                )
            )
            true
        )

        (map-set expenditure-reports expenditure-id {
            project-id: project-id,
            disbursement-id: disbursement-id,
            category: category,
            amount: amount,
            description: description,
            vendor: vendor,
            invoice-reference: invoice-reference,
            reported-by: tx-sender,
            timestamp: stacks-block-height,
            verified: false,
            verified-by: none,
        })

        (var-set next-expenditure-id (+ expenditure-id u1))
        (ok expenditure-id)
    )
)

(define-public (verify-expenditure-report (expenditure-id uint))
    (let (
            (expenditure-data (unwrap! (map-get? expenditure-reports expenditure-id)
                err-expenditure-not-found
            ))
            (project-data (unwrap! (map-get? projects (get project-id expenditure-data))
                err-not-found
            ))
        )
        (asserts!
            (or
                (is-eq tx-sender contract-owner)
                (is-authorized-auditor tx-sender)
            )
            err-unauthorized
        )
        (asserts! (not (get verified expenditure-data)) err-already-exists)
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)

        (map-set expenditure-reports expenditure-id
            (merge expenditure-data {
                verified: true,
                verified-by: (some tx-sender),
            })
        )
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
        (list
            u1             u2             u3             u4             u5
            u6             u7             u8             u9             u10
            u11             u12             u13             u14             u15
            u16             u17             u18             u19
            u20
        )
        u0
    )
)

(define-read-only (get-total-spent-funds)
    (fold calculate-total-spent
        (list
            u1             u2             u3             u4             u5
            u6             u7             u8             u9             u10
            u11             u12             u13             u14             u15
            u16             u17             u18             u19
            u20
        )
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

(define-read-only (get-milestone (milestone-id uint))
    (map-get? project-milestones milestone-id)
)

(define-read-only (get-expenditure-report (expenditure-id uint))
    (map-get? expenditure-reports expenditure-id)
)

(define-read-only (get-category-budget
        (project-id uint)
        (category (string-ascii 50))
    )
    (map-get? project-category-budgets {
        project-id: project-id,
        category: category,
    })
)

(define-read-only (get-project-category-spending
        (project-id uint)
        (category (string-ascii 50))
    )
    (match (map-get? project-category-budgets {
        project-id: project-id,
        category: category,
    })
        budget-data (some {
            allocated: (get allocated-amount budget-data),
            spent: (get spent-amount budget-data),
            remaining: (- (get allocated-amount budget-data) (get spent-amount budget-data)),
            utilization: (if (> (get allocated-amount budget-data) u0)
                (*
                    (/ (get spent-amount budget-data)
                        (get allocated-amount budget-data)
                    )
                    u100
                )
                u0
            ),
        })
        none
    )
)

(define-read-only (get-expenditure-count)
    (- (var-get next-expenditure-id) u1)
)

(define-read-only (get-project-milestone-progress (project-id uint))
    (fold calculate-milestone-progress
        (list
            u1             u2             u3             u4             u5
                        u6             u7             u8             u9             u10
                        u11             u12             u13             u14             u15
                        u16             u17             u18             u19
            u20
        ) {
        project-id: project-id,
        completed: u0,
        total: u0,
        released: u0,
    })
)

(define-private (calculate-milestone-progress
        (milestone-id uint)
        (progress {
            project-id: uint,
            completed: uint,
            total: uint,
            released: uint,
        })
    )
    (match (map-get? project-milestones milestone-id)
        milestone-data (if (is-eq (get project-id milestone-data) (get project-id progress))
            {
                project-id: (get project-id progress),
                completed: (if (is-eq (get status milestone-data) "completed")
                    (+ (get completed progress) u1)
                    (get completed progress)
                ),
                total: (+ (get total progress) u1),
                released: (if (is-eq (get status milestone-data) "completed")
                    (+ (get released progress)
                        (get fund-percentage milestone-data)
                    )
                    (get released progress)
                ),
            }
            progress
        )
        progress
    )
)

;; Public Engagement System Functions

(define-public (submit-project-rating
        (project-id uint)
        (rating uint)
        (comment (string-utf8 500))
    )
    (let (
            (project-data (unwrap! (map-get? projects project-id) err-project-not-found))
            (existing-rating (map-get? project-ratings {
                project-id: project-id,
                citizen: tx-sender,
            }))
            (current-engagement (default-to {
                ratings-count: u0,
                feedback-count: u0,
                last-activity: u0,
            } (map-get? citizen-engagement tx-sender)))
        )
        ;; Validate rating is between 1-5
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        ;; Check if citizen has already rated this project
        (asserts! (is-none existing-rating) err-rating-exists)
        ;; Verify project exists and is active
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)

        ;; Store the rating
        (map-set project-ratings {
            project-id: project-id,
            citizen: tx-sender,
        } {
            rating: rating,
            comment: comment,
            timestamp: stacks-block-height,
        })

        ;; Update citizen engagement stats
        (map-set citizen-engagement tx-sender {
            ratings-count: (+ (get ratings-count current-engagement) u1),
            feedback-count: (get feedback-count current-engagement),
            last-activity: stacks-block-height,
        })
        (ok true)
    )
)

(define-public (submit-public-feedback
        (project-id uint)
        (feedback-text (string-utf8 1000))
        (category (string-ascii 50))
    )
    (let (
            (project-data (unwrap! (map-get? projects project-id) err-project-not-found))
            (feedback-id (var-get next-feedback-id))
            (current-engagement (default-to {
                ratings-count: u0,
                feedback-count: u0,
                last-activity: u0,
            } (map-get? citizen-engagement tx-sender)))
            (current-project-feedback-count (default-to u0 (map-get? project-feedback-counter project-id)))
        )
        ;; Verify project exists and is active
        (asserts! (is-eq (get status project-data) "active") err-project-inactive)
        ;; Validate feedback category
        (asserts! (is-valid-feedback-category category) err-invalid-feedback-category)

        ;; Store the feedback
        (map-set public-feedback feedback-id {
            project-id: project-id,
            citizen: tx-sender,
            feedback-text: feedback-text,
            category: category,
            timestamp: stacks-block-height,
        })

        ;; Update feedback counter
        (var-set next-feedback-id (+ feedback-id u1))
        (map-set project-feedback-counter project-id (+ current-project-feedback-count u1))

        ;; Update citizen engagement stats
        (map-set citizen-engagement tx-sender {
            ratings-count: (get ratings-count current-engagement),
            feedback-count: (+ (get feedback-count current-engagement) u1),
            last-activity: stacks-block-height,
        })
        (ok feedback-id)
    )
)

(define-private (is-valid-category (category (string-ascii 50)))
    (or
        (is-eq category "personnel")
        (is-eq category "equipment")
        (is-eq category "materials")
        (is-eq category "services")
        (is-eq category "transportation")
        (is-eq category "utilities")
        (is-eq category "maintenance")
        (is-eq category "consulting")
        (is-eq category "training")
        (is-eq category "other")
    )
)

(define-private (is-valid-feedback-category (category (string-ascii 50)))
    (or
        (is-eq category "general")
        (is-eq category "progress")
        (is-eq category "quality")
        (is-eq category "timeline")
        (is-eq category "budget")
        (is-eq category "communication")
        (is-eq category "impact")
        (is-eq category "suggestion")
        (is-eq category "complaint")
        (is-eq category "praise")
    )
)

;; Public Engagement System Read-Only Functions

(define-read-only (get-project-average-rating (project-id uint))
    ;; This is a simplified version that returns the project-id for now
    ;; In a full implementation, this would aggregate all ratings for the project
    (if (is-some (map-get? projects project-id))
        (some project-id) ;; Placeholder - would calculate actual average
        none
    )
)

(define-read-only (get-project-feedback-summary (project-id uint))
    (let ((feedback-count (default-to u0 (map-get? project-feedback-counter project-id))))
        {
            project-id: project-id,
            total-feedback: feedback-count,
        }
    )
)

(define-read-only (get-citizen-engagement-stats (citizen principal))
    (default-to {
        ratings-count: u0,
        feedback-count: u0,
        last-activity: u0,
    } (map-get? citizen-engagement citizen))
)

(define-read-only (get-project-rating-distribution (project-id uint))
    ;; This is a simplified version that returns basic structure
    ;; In a full implementation, this would aggregate all rating distributions
    (if (is-some (map-get? projects project-id))
        {
            project-id: project-id,
            rating-1: u0,
            rating-2: u0,
            rating-3: u0,
            rating-4: u0,
            rating-5: u0,
        }
        {
            project-id: u0,
            rating-1: u0,
            rating-2: u0,
            rating-3: u0,
            rating-4: u0,
            rating-5: u0,
        }
    )
)

(define-read-only (get-project-rating (project-id uint) (citizen principal))
    (map-get? project-ratings {
        project-id: project-id,
        citizen: citizen,
    })
)

(define-read-only (get-feedback-entry (feedback-id uint))
    (map-get? public-feedback feedback-id)
)

(define-read-only (get-project-feedback-count (project-id uint))
    (default-to u0 (map-get? project-feedback-counter project-id))
)

;; Simplified read-only functions without fold operations
;; Note: These functions provide basic functionality that can be extended
;; in future versions with more advanced aggregation capabilities
