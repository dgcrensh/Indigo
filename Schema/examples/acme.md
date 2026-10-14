# Acme

5 screens. Positions and sizes are in points, measured from each screen's top-left corner. Regions are listed back to front, with the regions inside them nested under them; a region without a kind is open.

- [Login](#login)
- [Login (Desktop)](#login-desktop)
- [Reset Password](#reset-password)
- [Settings](#settings)
- [Account Menu](#account-menu)

## Login

- Kind: screen
- Viewport: iPhone 15, 393 × 852
- Variants (Login): [Login (Desktop)](#login-desktop)

Regions:

- **Logo** (image): x 148, y 96, 96 × 96.
  App logo, centered. No text.
- **Sign-in form** (container): x 16, y 240, 361 × 264.
  Vertically stacked form, centered.
  - **Email field** (input): x 32, y 256, 329 × 44.
    Single-line input with placeholder 'you@example.com'. Label above it.
  - **Password field** (input): x 32, y 316, 329 × 44.
    Secure input. A show/hide toggle sits at the trailing edge.
  - **Sign in** (button): x 32, y 384, 329 × 48.
    Primary button. Disabled until both fields have text.
    Links to [Settings](#settings) (click, after a successful sign-in).
  - **Forgot password** (button): x 32, y 456, 140 × 24.
    Text-style link button.
    Links to [Reset Password](#reset-password) (click).
- **Footer** (text): x 16, y 788, 361 × 32.
  Version number and a link to the privacy policy, small and muted.

## Login (Desktop)

- Kind: screen
- Viewport: Desktop, 1440 × 900
- Variants (Login): [Login](#login)

Regions:

- **Hero** (image): x 0, y 0, 720 × 900.
  Product illustration filling the left half.
- **Sign-in form** (container): x 880, y 300, 400 × 296.
  Same fields as the phone layout, in a card.
  - **Email field** (input): x 904, y 324, 352 × 44.
    Single-line input with placeholder 'you@example.com'.
  - **Password field** (input): x 904, y 384, 352 × 44.
    Secure input with a show/hide toggle.
  - **Sign in** (button): x 904, y 452, 352 × 48.
    Primary button. Return in either field also signs in.
    Links to [Settings](#settings) (click, after a successful sign-in).
  - **Forgot password** (button): x 904, y 524, 140 × 24.
    Text-style link button.
    Links to [Reset Password](#reset-password) (click).

## Reset Password

- Kind: screen
- Viewport: iPhone 15, 393 × 852

Regions:

- **Back** (navigation): x 16, y 56, 80 × 32.
  Back button to the previous screen.
  Links to [Login](#login) (click).
- **Instructions** (text): x 16, y 120, 361 × 64.
  "Enter your email and we'll send you a reset link."
- **Email field** (input): x 16, y 200, 361 × 44.
  Prefilled with the email from the Login screen if there was one.
- **Send link** (button): x 16, y 268, 361 × 48.
  Primary button. On success, replaces the form with a confirmation message.

## Settings

- Kind: screen
- Viewport: iPhone 15, 393 × 852

Regions:

- **Navigation bar** (navigation): x 0, y 48, 393 × 52.
  Large title 'Settings'.
  - **Account button** (button): x 337, y 56, 40 × 36.
    Avatar of the signed-in user.
    Links to [Account Menu](#account-menu) (click).
- **Settings list** (list): x 0, y 100, 393 × 752.
  Grouped list. Rows push their own screens (not described yet).
  Scrolls vertically, content 393 × 1200.
  - **Notifications row** (toggle): x 16, y 116, 361 × 44.
    Toggle for push notifications.
  - **Appearance row** (picker): x 16, y 168, 361 × 44.
    Picker: System, Light, Dark.
  - **About section** (container): x 16, y 1000, 361 × 180.
    Below the fold: version, licenses, and support links.

## Account Menu

- Kind: menu
- Viewport: Custom, 240 × 136

Regions:

- **Signed in as** (text): x 12, y 8, 216 × 36.
  The user's name and email, not clickable.
- **Settings** (menu-item): x 4, y 52, 232 × 36.
  Links to [Settings](#settings).
- **Sign out** (menu-item): x 4, y 92, 232 × 36.
  Signs out without confirming.
  Links to [Login](#login) (click).
