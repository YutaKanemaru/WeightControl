import Testing
@testable import WeightControlApp

/// Pro を使えるかどうかのルール（ProAccessPolicy）のテスト
struct ProAccessPolicyTests {
    @Test("購入していれば、スイッチやビルドに関係なく使える")
    func purchasedIsAlwaysUnlocked() {
        #expect(ProAccessPolicy.isUnlocked(isPurchased: true, isDebugTrialOn: false, allowsDebugTrial: false))
        #expect(ProAccessPolicy.isUnlocked(isPurchased: true, isDebugTrialOn: true, allowsDebugTrial: true))
    }

    @Test("Debug ビルドでは「Pro を試す」がオンなら使える")
    func debugTrialUnlocksInDebugBuild() {
        #expect(ProAccessPolicy.isUnlocked(isPurchased: false, isDebugTrialOn: true, allowsDebugTrial: true))
        #expect(!ProAccessPolicy.isUnlocked(isPurchased: false, isDebugTrialOn: false, allowsDebugTrial: true))
    }

    @Test("Release ビルドでは、スイッチがオンでも購入しないと使えない")
    func debugTrialIsIgnoredInReleaseBuild() {
        #expect(!ProAccessPolicy.isUnlocked(isPurchased: false, isDebugTrialOn: true, allowsDebugTrial: false))
    }
}
