"""Money helpers. Amounts are integer cents; rates are basis points (1700 = 17%)."""
from decimal import Decimal, ROUND_HALF_EVEN


def apply_rate(cents, rate_bp):
    """cents * rate_bp / 10000, rounded half to even to a whole cent."""
    value = Decimal(int(cents)) * Decimal(int(rate_bp)) / Decimal(10000)
    return int(value.quantize(Decimal(1), rounding=ROUND_HALF_EVEN))


def split(cents, numerator, denominator):
    """cents * numerator / denominator, rounded half to even to a whole cent."""
    value = Decimal(int(cents)) * Decimal(int(numerator)) / Decimal(int(denominator))
    return int(value.quantize(Decimal(1), rounding=ROUND_HALF_EVEN))


def fmt(cents):
    """1234 -> '12.34', -5 -> '-0.05'."""
    sign = "-" if cents < 0 else ""
    cents = abs(int(cents))
    return f"{sign}{cents // 100}.{cents % 100:02d}"


def is_cents(value):
    return isinstance(value, int) and not isinstance(value, bool)
