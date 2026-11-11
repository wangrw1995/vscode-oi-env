# -*- coding: utf-8 -*-
"""Python 自检脚本：语法高亮、Pylance 提示、运行/调试都能用。"""

import sys
from dataclasses import dataclass


@dataclass
class Item:
    name: str
    price: float


def total(items: list[Item]) -> float:
    return sum(i.price for i in items)


if __name__ == "__main__":
    items = [Item("keyboard", 199.0), Item("mouse", 89.5)]
    print("Python:", sys.version.split()[0])
    print("items:", [i.name for i in items])
    print(f"total = {total(items):.2f}")
    print("PYTHON OK")
