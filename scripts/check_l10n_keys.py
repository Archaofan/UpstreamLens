"""校验 Swift 源码引用的本地化键都存在于 String Catalog。

为什么需要这个检查：键写错时 `Bundle.localizedString` 会静默回退成键本身，
于是英文看起来完全正常、中文却显示英文。编译器查不出来，JSON 也依然合法，
只能靠显式校验。

同时检查每个键是否都补齐了 en 与 zh-Hans：
- 缺 en 会导致 en.lproj 生成不全，系统语言识别出错；
- 缺 zh-Hans 会让中文用户看到英文。

用法：python build/check_l10n_keys.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, 'Sources', 'App', 'Localizable.xcstrings')
SRC = os.path.join(ROOT, 'Sources')

# AppLocalization.string("...") 与 L10n.format("...")
PATTERNS = [
    re.compile(r'AppLocalization\.string\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'L10n\.format\(\s*"((?:[^"\\]|\\.)*)"'),
]

PLACEHOLDER = re.compile(r'\{([a-zA-Z][a-zA-Z0-9]*)\}')


def main() -> int:
    if not os.path.exists(CATALOG):
        print('catalog not found: %s' % CATALOG)
        return 1
    with open(CATALOG, encoding='utf-8') as handle:
        strings = json.load(handle)['strings']

    missing = []
    checked = 0
    for dirpath, _, names in os.walk(SRC):
        for name in names:
            if not name.endswith('.swift'):
                continue
            path = os.path.join(dirpath, name)
            raw = open(path, encoding='utf-8').read()
            # 去掉注释行：文档里的用法示例会被正则误当成真实调用。
            text = '\n'.join('' if line.lstrip().startswith('//') else line
                             for line in raw.split('\n'))
            for pattern in PATTERNS:
                for match in pattern.finditer(text):
                    key = match.group(1)
                    checked += 1
                    if key not in strings:
                        line = text[:match.start()].count('\n') + 1
                        missing.append((os.path.relpath(path, ROOT), line, key))

    problems = 0
    print('keys referenced: %d' % checked)
    if missing:
        print('MISSING FROM CATALOG: %d' % len(missing))
        for rel, line, key in missing[:40]:
            print('  %s:%d  %s' % (rel, line, key[:90]))
        problems += len(missing)

    # 占位符一致性：同一个键的 en 与 zh-Hans 必须使用同一组占位符，
    # 否则某种语言下会残留 {name} 或漏掉一个值。
    for key, entry in strings.items():
        localizations = entry.get('localizations', {})
        sets = {}
        for language, payload in localizations.items():
            value = payload.get('stringUnit', {}).get('value')
            if value:
                sets[language] = set(PLACEHOLDER.findall(value))
        if len(sets) > 1 and len({frozenset(v) for v in sets.values()}) > 1:
            print('PLACEHOLDER MISMATCH: %s' % key[:70])
            for language, names in sorted(sets.items()):
                print('   %-8s %s' % (language, sorted(names)))
            problems += 1

    no_en = [k for k, v in strings.items() if 'en' not in v.get('localizations', {})]
    no_zh = [k for k, v in strings.items()
             if v.get('localizations', {}).get('zh-Hans', {}).get('stringUnit', {}).get('state') != 'translated']
    print('keys without en entry: %d' % len(no_en))
    print('keys without translated zh-Hans: %d' % len(no_zh))
    for key in no_en[:10]:
        print('  no-en: %s' % key[:90])
    for key in no_zh[:10]:
        print('  no-zh: %s' % key[:90])
    problems += len(no_en) + len(no_zh)

    if problems:
        print('---')
        print('%d problem(s)' % problems)
        return 1
    print('---')
    print('all localization keys resolve (total %d)' % len(strings))
    return 0


if __name__ == '__main__':
    sys.exit(main())
