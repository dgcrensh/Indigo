import DescriberCore
import Foundation

/// Builds the example project in `Schema/examples/acme.uidesc`. The files there are written from this model by
/// `ExampleProjectTests.testRegenerateExample`, never by hand.
enum AcmeExample {
    static let login = ScreenID("6513270e-269e-4d37-b2a7-4de452e6b438")
    static let loginDesktop = ScreenID("d23f0824-128b-4f33-8c5c-7fd0a6a3a450")
    static let resetPassword = ScreenID("9531985d-5d9d-49f8-9818-e811892f902b")
    static let settings = ScreenID("36f675cc-81e7-4ef5-a8e2-5d940ed90475")
    static let accountMenu = ScreenID("6b0d549b-6f03-475a-9600-a35a099950d8")

    static func make() -> Project {
        Project(
            name: "Acme",
            screens: [
                loginScreen(), loginDesktopScreen(), resetPasswordScreen(), settingsScreen(), accountMenuScreen(),
            ],
            variantGroups: [VariantGroup(name: "Login", screens: [login, loginDesktop])]
        )
    }

    private static func region(
        _ id: String,
        _ title: String,
        _ kind: RegionKind = .open,
        _ frame: (Int, Int, Int, Int),
        _ description: String,
        scroll: Scroll? = nil,
        links: [Link] = [],
        children: [Region] = []
    ) -> Region {
        Region(
            id: RegionID(id),
            title: title,
            kind: kind,
            frame: Frame(x: frame.0, y: frame.1, w: frame.2, h: frame.3),
            description: description,
            scroll: scroll,
            links: links,
            children: children
        )
    }

    private static func loginScreen() -> Screen {
        Screen(
            id: login,
            name: "Login",
            viewport: Viewport(preset: "iphone-15", width: 393, height: 852),
            regions: [
                region(
                    "8d116ece-1738-47d9-bd9c-172411e20b8f", "Logo", .image, (148, 96, 96, 96),
                    "App logo, centered. No text."),
                region(
                    "90c192cf-d3ac-44af-8f21-ddb66cad4a26", "Sign-in form", .container, (16, 240, 361, 264),
                    "Vertically stacked form, centered.",
                    children: [
                        region(
                            "a170b338-3926-4059-b28c-105d1fb17c23", "Email field", .input, (32, 256, 329, 44),
                            "Single-line input with placeholder 'you@example.com'. Label above it."),
                        region(
                            "0fd630f1-f29d-4da9-953f-48f1a09f76b5", "Password field", .input, (32, 316, 329, 44),
                            "Secure input. A show/hide toggle sits at the trailing edge."),
                        region(
                            "0cb1e29c-658c-4a14-95e6-0af593bd04cf", "Sign in", .button, (32, 384, 329, 48),
                            "Primary button. Disabled until both fields have text.",
                            links: [Link(screen: settings, trigger: "click, after a successful sign-in")]),
                        region(
                            "8e81973e-0bec-47b0-b898-d190f9ebdacc", "Forgot password", .button, (32, 456, 140, 24),
                            "Text-style link button.",
                            links: [Link(screen: resetPassword, trigger: "click")]),
                    ]),
                region(
                    "6b4cb242-4a23-4596-a217-beaddbc496cb", "Footer", .text, (16, 788, 361, 32),
                    "Version number and a link to the privacy policy, small and muted."),
            ]
        )
    }

    private static func loginDesktopScreen() -> Screen {
        Screen(
            id: loginDesktop,
            name: "Login (Desktop)",
            viewport: Viewport(preset: "desktop", width: 1440, height: 900),
            regions: [
                region(
                    "92276658-1e27-41c0-8a6a-63ec24ede6a4", "Hero", .image, (0, 0, 720, 900),
                    "Product illustration filling the left half."),
                region(
                    "ae97ba94-d0ed-482f-8f6d-05584ef8aa38", "Sign-in form", .container, (880, 300, 400, 296),
                    "Same fields as the phone layout, in a card.",
                    children: [
                        region(
                            "923a7369-94e3-4f91-9a61-dbe22e44158b", "Email field", .input, (904, 324, 352, 44),
                            "Single-line input with placeholder 'you@example.com'."),
                        region(
                            "18f135d2-5f55-4203-b018-50c5a38fd547", "Password field", .input, (904, 384, 352, 44),
                            "Secure input with a show/hide toggle."),
                        region(
                            "907a70c3-1012-4037-b64c-e4228c38fb29", "Sign in", .button, (904, 452, 352, 48),
                            "Primary button. Return in either field also signs in.",
                            links: [Link(screen: settings, trigger: "click, after a successful sign-in")]),
                        region(
                            "7f150524-34b9-45df-9e77-69b10f4205b4", "Forgot password", .button, (904, 524, 140, 24),
                            "Text-style link button.",
                            links: [Link(screen: resetPassword, trigger: "click")]),
                    ]),
            ]
        )
    }

    private static func resetPasswordScreen() -> Screen {
        Screen(
            id: resetPassword,
            name: "Reset Password",
            viewport: Viewport(preset: "iphone-15", width: 393, height: 852),
            regions: [
                region(
                    "c6f87718-6d76-407e-881e-d162ae2eb154", "Back", .navigation, (16, 56, 80, 32),
                    "Back button to the previous screen.",
                    links: [Link(screen: login, trigger: "click")]),
                region(
                    "ec66a787-95e7-41d1-b731-af10506bf2ef", "Instructions", .text, (16, 120, 361, 64),
                    "\"Enter your email and we'll send you a reset link.\""),
                region(
                    "3f98e277-4cbd-47ad-9c90-a9587403e430", "Email field", .input, (16, 200, 361, 44),
                    "Prefilled with the email from the Login screen if there was one."),
                region(
                    "c7a2ea20-b2f1-4c94-ae05-319acb5c7427", "Send link", .button, (16, 268, 361, 48),
                    "Primary button. On success, replaces the form with a confirmation message."),
            ]
        )
    }

    private static func settingsScreen() -> Screen {
        Screen(
            id: settings,
            name: "Settings",
            viewport: Viewport(preset: "iphone-15", width: 393, height: 852),
            regions: [
                region(
                    "4cdd2055-930d-4eaf-94f4-733f3e7d1bfb", "Navigation bar", .navigation, (0, 48, 393, 52),
                    "Large title 'Settings'.",
                    children: [
                        region(
                            "57ee05cd-e009-42c7-bebf-f20686734721", "Account button", .button, (337, 56, 40, 36),
                            "Avatar of the signed-in user.",
                            links: [Link(screen: accountMenu, trigger: "click")])
                    ]),
                region(
                    "9be4bcfc-49b6-4a08-b2e6-cc3ababced20", "Settings list", .list, (0, 100, 393, 752),
                    "Grouped list. Rows push their own screens (not described yet).",
                    scroll: Scroll(axis: .vertical, contentWidth: 393, contentHeight: 1200),
                    children: [
                        region(
                            "830e07bc-1e39-4f10-92bd-4acefaecbd38", "Notifications row", .toggle, (16, 116, 361, 44),
                            "Toggle for push notifications."),
                        region(
                            "5790f82e-c1d3-4cff-aa3a-f4d46b0a18e8", "Appearance row", .picker, (16, 168, 361, 44),
                            "Picker: System, Light, Dark."),
                        region(
                            "6bf46c69-7d2c-4f82-aeea-cbe226e87555", "About section", .container, (16, 1000, 361, 180),
                            "Below the fold: version, licenses, and support links."),
                    ]),
            ]
        )
    }

    private static func accountMenuScreen() -> Screen {
        Screen(
            id: accountMenu,
            name: "Account Menu",
            kind: .menu,
            viewport: Viewport(width: 240, height: 136),
            regions: [
                region(
                    "13deef86-ab10-41d0-b646-e1f40a097c97", "Signed in as", .text, (12, 8, 216, 36),
                    "The user's name and email, not clickable."),
                region(
                    "ca02135e-92b1-43f2-8ede-0d7ac3baea9e", "Settings", .menuItem, (4, 52, 232, 36), "",
                    links: [Link(screen: settings)]),
                region(
                    "57124242-5051-41cc-917f-9acae01f5057", "Sign out", .menuItem, (4, 92, 232, 36),
                    "Signs out without confirming.",
                    links: [Link(screen: login, trigger: "click")]),
            ]
        )
    }
}
