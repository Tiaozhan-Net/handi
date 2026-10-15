# 作业测评模板 — test-homework-check

说明：本仓库用于作为作业模板与自动测评示例。请同学把本次作业的全部代码完成在仓库根目录下的 `main.go` 文件中，不要修改除此之外的其他文件，按下面说明提交，Push 后会自动触发 GitHub Actions 测评。

## 作业要求
- 代码必须全部写在 `main.go` 中；其他文件除非特殊说明不要修改。
- 请确保 `main.go` 的包名为 `main` 并且可以通过 `go run main.go` 本地运行。

## 本地运行与调试
1. 克隆你的作业仓库：
   ```bash
   git clone https://github.com/<your-account>/<your-repositories-name>
   cd <your-repositories-name>
   ```
2. 在本地运行：
   ```bash
   go run main.go
   ```

## 提交步骤
1. 在本地完成 `main.go` 的实现并提交到 `main` 分支：
   ```bash
   git add main.go
   git commit
   git push origin main
   ```
2. Push 到 `main` 后，仓库中的 GitHub Actions workflow 会自动触发测评。
3. 前往 GitHub 仓库页面 → Actions，查看对应 workflow 的运行状态和日志。通过/失败的结果与 Actions 日志会记录测评细节。

## 测评与得分说明
- 测评由仓库内的 workflow 调用预置的测试脚本或测试用例）。
- 测评通过/失败由测试脚本决定；若失败请根据 Actions 日志修复并重新 push。

## 常见问题与排查
- Actions 未触发：
  - 确认你 push 到的是 `main` 分支（或 workflow 指定的触发分支）。
  - 确认仓库中 `.github/workflows/` 下存在 workflow 且包含 `on: push`。
- 测评提示找不到 `main.go`：确认 `main.go` 在仓库根目录并已被提交并 push。

## 请注意
- 请务必把作业代码写在 `main.go`，否则测评脚本可能无法正确定位到你的实现而导致测评失败。
- 不要修改模板中的 workflow 配置，除非你非常确定修改内容不会影响测评流程。
