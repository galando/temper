"""Tax rates per region, in basis points."""
RATES_BP = {"IL": 1700, "DE": 1900, "UK": 2000, "US-NY": 887, "NONE": 0}


def rate_for(region):
    return RATES_BP[region]
