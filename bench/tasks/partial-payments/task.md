Customers want to pay invoices in parts, and finance needs refunds. Build partial payments and refunds.

- `POST /invoices/{id}/payments` takes `{"amount_cents": ..., "method": ...}`. `amount_cents` is optional: without it, the payment is the invoice's whole balance (what paying does today). It must be a whole number of cents above 0, and not more than the balance (more is a 409 conflict).
- An invoice's paid amount is its payments minus their refunds; its balance is its total minus the paid amount. An invoice that has been paid in part has the status `partially_paid`; when the balance reaches 0 it is `paid`. A `partially_paid` invoice takes more payments like an issued one. Draft and void invoices take none.
- `POST /invoices/{id}/refunds` takes `{"payment_id": ..., "amount_cents": ...}` and refunds part or all of one payment of that invoice. A payment that is not a payment of this invoice answers 404. Refunding more than is left of that payment is a 409 conflict. After a refund the status follows the money: `paid` goes back to `partially_paid`, or to `issued` when nothing paid is left.
- An invoice with a paid amount above 0 cannot be voided (409 conflict).
- A credit note credits only the balance: its amount is the invoice's balance when it is created, and an invoice with a balance of 0 cannot be credited (409 conflict).
- `GET /invoices/{id}` (and every invoice the API returns) gains `paid_cents` and `balance_cents`. The invoices CSV export gains `paid` and `balance` columns, after `total`.
