import AppKit

enum AGAssets {
    static let brandIcon = image(named: "BrandIcon")
    static let splashHero = image(named: "SplashHero")

    private static func image(named name: String) -> NSImage? {
        Bundle.module.image(forResource: NSImage.Name(name))
    }
}
