1. Only a draft invoice can get a discount; any other status is a 409 conflict.
2. The discount comes off before tax, line by line: each line's subtotal is reduced by the percent (the discount on each line rounded half to even), and the tax is computed per line on the reduced amount. `subtotal_cents` stays the amount before the discount, `discount_cents` is the sum of the line discounts, and the total is subtotal minus discount plus tax.
3. A clerk may give up to 20%; an admin up to 40%. A clerk asking for more than 20% gets 403 forbidden. More than 40% is never allowed: 400 validation.
4. Setting a discount again replaces the old one, and 0 removes it. A line added after the discount gets the discount too.
5. The invoices CSV export shows the discount in a `discount` column, the last column.
