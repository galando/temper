1. A late fee is its own invoice to the same customer, issued at once, with one line: description `Late fee for <number of the overdue invoice>` (for example `Late fee for INV-0001`), quantity 1.
2. The fee is 2% of the overdue invoice's total, rounded half to even, and never less than 5.00 (500 cents).
3. There is a grace period: an invoice is overdue only when the tenant's today is more than 7 days after its due date.
4. An invoice is charged a late fee once, ever, however many days the job runs.
5. Invoices with a total under 20.00 (2000 cents) are never charged a late fee.
6. Late fee invoices themselves never get a late fee.
