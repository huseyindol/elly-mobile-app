# Elly Mobile App — Agent Rehberi (Antigravity / Cursor / genel)

Tüm AI asistanları için ortak giriş noktası. Kanonik proje rehberi **`CLAUDE.md`**'dir — önce onu oku.

## Okuma sırası

1. `CLAUDE.md` — stack, dizin yapısı, mimari kurallar, komutlar, git.
2. Bu dosya — agent/skill/rule dosyalarının yeri.
3. Orchestrator'dan geliyorsan: `../AGENTS.md` ve `../.agents/skills/mobile-lead/SKILL.md`.

## Yapılandırma nerede

| Konum | Araç | İçerik |
|---|---|---|
| `CLAUDE.md` | hepsi | Tek kaynak: kurallar ve iş akışı |
| `.claude/agents/` | Claude Code | `test-writer`, `ui-reviewer` |
| `.claude/skills/` | Claude Code | `karpathy-guidelines`, `ponytail`, `ponytail-review` |
| `.agents/rules/` | Antigravity | `ponytail.md` (her zaman aktif workspace kuralı) |
| `.agents/skills/` | Antigravity | `karpathy-guidelines` |
| `.cursor/rules/` | Cursor | `karpathy-guidelines.mdc`, `ponytail.mdc` (`alwaysApply`) |

## Roller

| Rol | Sahiplik | Tanım |
|---|---|---|
| **mobile-lead** (Orchestrator'da) | Planlama, uygulama, doğrulama, commit | `../.agents/skills/mobile-lead/SKILL.md` |
| **test-writer** | `test/` altındaki Dart testleri | `.claude/agents/test-writer.md` |
| **ui-reviewer** | Ekran/bileşen UI-UX ve a11y review (salt-okunur) | `.claude/agents/ui-reviewer.md` |

## Davranış

- **Karpathy:** düşün → sor, basit tut, cerrahi değiş, doğrulanabilir hedefle ilerle.
- **Ponytail:** işi tam çözen en küçük değişiklik; istenmeyen soyutlama, seçenek, bağımlılık yok.
  Doğrulama, hata yönetimi, güvenlik ve erişilebilirlikten asla kısma.

## Doğrulama

```bash
flutter analyze && flutter test
```

`main` üzerinde commit; **push yok**. Gizli bilgi commit edilmez (bkz. `CLAUDE.md` → Komutlar).
