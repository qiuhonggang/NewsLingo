# NewsLingo .newslingo 双语学习包 v2

每篇新闻使用一个 UTF-8 JSON 文件。字段如下。

| 字段 | 内容 |
| --- | --- |
| `version` | 整数 `2` |
| `title` / `titleZh` | 英文导读标题及其简体中文译名 |
| `source` | `name` 发布方，`title` 来源原始标题，`url` 直接指向原文，`published` 为原文的 `YYYY-MM-DD` |
| `level` | `A2`、`B1`、`B2`、`C1`、`C2` 之一 |
| `paragraphs` | 按阅读顺序排列的段落对象。每个对象有 `en`、`zh`、`sentences` |
| `questions` | 4–8 道题，包含主旨、细节、推断 |

`sentences` 是有序的 `{ "en": "...", "zh": "..." }` 句对数组。英文句子用空格拼接后须与段落 `en` 相同。中文句子直接拼接后须与段落 `zh` 相同，校验时忽略空白。中文按整段语境理解，再在句对边界落句，以保证两种阅读视图共享一份译文。

每道题有 `kind`（`mainIdea`、`detail`、`inference` 或 `vocabulary`）、`prompt`、`choices`（四个不同英文选项）、`answer`（从 0 开始的整数）、`evidence`（对学习包英文正文逐字摘取的连续文字，18–800 字符）、`explanation`（简体中文）。正文至少 100 个英文单词和 5 个完整句子。

本机校验和导入。

```sh
"/Applications/NewsLingo.app/Contents/MacOS/NewsLingo" --validate "/绝对路径/文章.newslingo"
open -b app.newslingo.reader "/绝对路径/文章.newslingo"
```

校验成功时检查 `bilingualParagraphs` 与 `alignedSentences`，均应大于 0。完整示例在 NewsLingo 的「设置 → AI 导入」。
