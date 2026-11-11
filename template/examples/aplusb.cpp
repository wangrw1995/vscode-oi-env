#include <iostream>

// A+B problem —— 最小可用的 OI 模板。
// 按 F5 编译运行，或在 CPH-NG 里按 Ctrl+Alt+B 用 tests/ 下的样例评测。
int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);

    long long a = 0, b = 0;
    if (!(std::cin >> a >> b)) return 0;
    std::cout << a + b << '\n';
    return 0;
}
