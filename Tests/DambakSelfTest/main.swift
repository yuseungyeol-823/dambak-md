import DambakCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let duplicate = MarkdownRenderer.render("## 중복\n\n## 중복")
check(duplicate.headings.map(\.id) == ["중복", "중복-1"], "중복 제목 앵커")
let malicious = MarkdownRenderer.render("<script>alert(1)</script>\n\n[bad](javascript:alert(1))\n\n<img src=x onerror=alert(1)>")
check(!malicious.html.contains("<script"), "스크립트 차단")
check(!malicious.html.contains("javascript:"), "위험 스킴 차단")
check(!malicious.html.contains("onerror="), "이벤트 핸들러 차단")
let relative = MarkdownRenderer.render("![그림](이미지%20자료/샘플%20그림.png) [다음](긴%20문서.md)")
check(relative.html.contains("dambak-resource://image/"), "상대 이미지")
check(relative.html.contains("긴%20문서.md"), "상대 문서")
check(MarkdownRenderer.safeURL("../비밀.png", image: true) == nil, "상위 폴더 접근 차단")
print("렌더러 자체 검증 7개 통과")
