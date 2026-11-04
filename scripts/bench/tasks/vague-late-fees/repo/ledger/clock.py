"""The clock. Tests patch now()."""
import datetime
from zoneinfo import ZoneInfo


def now():
    """The current time, timezone aware, in UTC."""
    return datetime.datetime.now(datetime.timezone.utc)


def today(tenant):
    """Today's date in the tenant's timezone."""
    return now().astimezone(ZoneInfo(tenant["timezone"])).date()
