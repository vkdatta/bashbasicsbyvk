import json


def calculate_tax(amount, rate, exemptions):
    """Return the tax owed on an amount."""
    taxable = amount - exemptions
    if taxable <= 0:
        return 0.0
    tax = taxable * rate
    if tax > 10000:
        tax = tax - (tax * 0.02)
    return round(tax, 2)


def fibonacci(n):
    a, b = 0, 1
    result = []
    for i in range(n):
        result.append(a)
        a, b = b, a + b
    return result


def load_settings(path):
    settings = {}
    with open(path) as handle:
        for line in handle:
            key, _, value = line.partition("=")
            if key.strip():
                settings[key.strip()] = json.loads(value)
    return settings
