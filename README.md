# FoundationModels-Playground

A SwiftUI playground for on-device language models through Apple's Foundation Models API. Turns user input into structured query parameters, routes questions, and answers questions about a bundled card statement with tool calling.

It currently runs Google's [Gemma 4 E4B](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) on device with [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) (Swift package, 0.18.1), behind the Foundation Models `LanguageModel` protocol (`GemmaLanguageModel.swift`), with thinking and speculative decoding on. Every page uses a stock `LanguageModelSession`, so switching back to Apple's model is a change to `OnDeviceModel.languageModel`.

Requires Xcode 27+ and iOS or macOS 27. The app downloads the 3.66 GB model file from Hugging Face on first launch.

| **Query Parameters 1** | **Query Parameters 2** |
| :----: | :----: |
| <img width="1206" height="2622" alt="Screenshot iPhone 17 Pro 2026-09-04 at 09 14 28" src="https://github.com/user-attachments/assets/cf2d22d6-4eb5-4fd0-937c-2572c14722ee" /> | <img width="1206" height="2622" alt="Screenshot iPhone 17 Pro 2026-09-04 at 09 14 50" src="https://github.com/user-attachments/assets/7cecfc94-32dd-4a05-b4a3-438a540f898a" /> |

| **Inquiry Router 1** | **Inquiry Router 2** |
| :----: | :----: |
| <img width="1206" height="2622" alt="Screenshot iPhone 17 Pro 2026-09-04 at 09 14 55" src="https://github.com/user-attachments/assets/9ca791f9-fb2b-4d35-a846-ee7ca5e5e858" /> | <img width="1206" height="2622" alt="Screenshot iPhone 17 Pro 2026-09-04 at 09 15 23" src="https://github.com/user-attachments/assets/bb2d43b9-fd8e-4c6f-bcda-40504025b8ef" /> |
