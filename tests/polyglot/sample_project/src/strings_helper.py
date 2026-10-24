def flip_sentence(text):
    parts = text.split(" ")
    flipped = []
    for part in parts:
        flipped.insert(0, part)
    return " ".join(flipped)


def clamp(value, low, high):
    if value < low:
        return low
    if value > high:
        return high
    return value
