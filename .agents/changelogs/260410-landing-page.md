# 260410 - Landing Page, Privacy Policy & Terms

## Summary

Created a beautiful landing page with hero section, feature cards, and login indicator. Also added privacy policy and terms of service pages.

## Changes

### Landing Page (`home.html.heex`)
- **Fixed top navigation bar** with glassmorphism effect, containing logo, theme toggle, and login indicator
- **Login indicator** shows green ping dot + user email when authenticated; shows "Sign In" and "Get Started" buttons when not
- **Hero section** with:
  - Animated badge ("Multi-Agent AI Workspace")
  - Gradient headline text ("orchestrate" in orange-to-rose gradient)
  - Compelling CTA description
  - Contextual buttons (Dashboard when logged in, Register/Sign In when not)
  - Fake chat UI mockup showing the product in action with streaming dots
  - Decorative background orbs and dot grid pattern
- **Features section** (6 horizontal cards in a responsive grid):
  1. Multi-Agent Orchestration (orange icon)
  2. Real-Time Streaming (emerald icon)
  3. Extensible Tool System (blue icon)
  4. Organizations & Teams (violet icon)
  5. Telegram Integration (amber icon)
  6. Context Management (pink icon)
- **CTA section** with gradient background
- **Footer** with logo, Privacy Policy link, Terms of Service link, and copyright

### Privacy Policy Page (`privacy.html.heex`)
- 10 sections covering: information collection, usage, sharing, security, retention, rights, children's privacy, international transfers, policy changes, and contact
- Mentions third-party AI providers (OpenAI, Google Gemini) and Telegram integration

### Terms of Service Page (`terms.html.heex`)
- 15 sections covering definitions, registration, acceptable use, AI agents, third-party providers, Telegram, IP, organizations, disclaimers, liability, indemnification, termination, changes, governing law, and contact
- **Prominent warning callout box** about third-party AI providers (OpenAI, Google Gemini, etc.) with details about data transmission and provider governance
- Styled amber warning box with icon

### Router Updates
- Added `GET /privacy` route → `PageController.privacy/2`
- Added `GET /terms` route → `PageController.terms/2`

### PageController Updates
- Added `privacy/2` and `terms/2` actions
- Updated `home/2` to pass `current_scope` for login state

### Test Updates
- Updated page controller test to check for new landing page content
- Added tests for `/privacy` and `/terms` routes

By: qwen-max/claude-sonnet-4-5 on Qwen Code
