import os

def mkdir(d: str) -> str:
    if not os.path.exists(d):
        os.mkdir(d)
    return d

def print_counts(data) -> str:
    max_len = 0
    for key, _ in data:
        max_len = max(max_len, len(key))
    for key, count in data:
        space = ' ' * (max_len - len(key))
        print(f'{key}:{space} {count}')
