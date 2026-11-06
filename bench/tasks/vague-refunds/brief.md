1. Only an admin may refund. A clerk who tries gets 403 forbidden.
2. A refund is allowed up to 60 days after the payment date (counting by the tenant's today). After that it is a 409 conflict.
3. Partial refunds are fine, but the refunds of an invoice can never add up to more than was paid (409 conflict).
4. A reason is required; a refund without one (or an empty one) is a 400 validation error.
5. When an invoice has been refunded in full, its status becomes `refunded`. A partly refunded invoice stays `paid`.
