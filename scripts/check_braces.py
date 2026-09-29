import sys

def check(path):
    src = open(path, encoding='utf-8').read()
    i, n = 0, len(src)
    state = 'code'  # code, line_comment, block_comment, string, multiline, interp
    depth_brace = depth_paren = 0
    interp = []
    line = 1
    imbalances = []
    BS = chr(92)
    while i < n:
        c = src[i]
        nxt = src[i+1] if i+1 < n else ''
        if c == '\n':
            line += 1
        if state == 'code':
            if c == '/' and nxt == '/':
                state = 'line_comment'; i += 2; continue
            if c == '/' and nxt == '*':
                state = 'block_comment'; i += 2; continue
            if c == '"':
                if src[i:i+3] == '"""':
                    state = 'multiline'; i += 3; continue
                state = 'string'; i += 1; continue
            if c == '{': depth_brace += 1
            elif c == '}': depth_brace -= 1
            elif c == '(': depth_paren += 1
            elif c == ')': depth_paren -= 1
            if depth_brace < 0 or depth_paren < 0:
                imbalances.append('line %d: negative depth' % line)
                depth_brace = depth_paren = 0
            i += 1; continue
        if state == 'line_comment':
            if c == '\n': state = 'code'
            i += 1; continue
        if state == 'block_comment':
            if c == '*' and nxt == '/':
                state = 'code'; i += 2; continue
            i += 1; continue
        if state == 'string':
            if c == BS:
                if nxt == '(':
                    interp.append(depth_paren); state = 'interp'; i += 2; continue
                i += 2; continue
            if c == '"':
                state = 'code'
            i += 1; continue
        if state == 'interp':
            if c == '(':
                depth_paren += 1
            elif c == ')':
                if depth_paren == interp[-1]:
                    interp.pop(); state = 'string'
                else:
                    depth_paren -= 1
            i += 1; continue
        if state == 'multiline':
            if c == BS:
                if nxt == '(':
                    interp.append(depth_paren); state = 'interp'; i += 2; continue
                i += 2; continue
            # Swift 要求结束三引号单独占一行（行首只允许空白）。
            # 否则字符串内容里的 ""（如 JSON 的 "":"") 会被误判成结束符，
            # 导致后续字符串内的花括号被误计。
            if c == '"' and src[i:i+3] == '"""':
                line_start = src.rfind('\n', 0, i) + 1
                if src[line_start:i].strip() == '':
                    state = 'code'; i += 3; continue
            i += 1; continue
    ok = depth_brace == 0 and depth_paren == 0 and state == 'code' and not imbalances
    return ok, 'depth_brace=%d depth_paren=%d end_state=%s %s' % (depth_brace, depth_paren, state, imbalances[:3])

import glob

files = sorted(
    glob.glob('Sources/**/*.swift', recursive=True)
    + glob.glob('Tests/**/*.swift', recursive=True))

if not files:
    print('no Swift files found - run this from the repository root')
    raise SystemExit(1)

bad = 0
for f in files:
    ok, info = check(f)
    if not ok:
        bad += 1
        print('FAIL %s: %s' % (f, info))
print('---')
print('checked %d files' % len(files))
print('all balanced' if bad == 0 else '%d files unbalanced' % bad)
raise SystemExit(1 if bad else 0)
