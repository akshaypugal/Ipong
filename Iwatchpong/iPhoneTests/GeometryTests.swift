import XCTest
import PongCore
@testable import WristPong

final class GeometryTests: XCTestCase {
    func testCameraProjectsTableInsideTheScreen() {
        let camera = CourtCamera()
        let size = CGSize(width: 390, height: 844)
        for (x, z) in [(-1.37, -0.76), (-1.37, 0.76), (1.37, -0.76), (1.37, 0.76), (0.0, 0.0)] {
            let p = camera.project(Vec3(x, 0, z), in: size)
            XCTAssertNotNil(p)
            if let p {
                XCTAssertTrue(p.x > -40 && p.x < size.width + 40, "x \(p.x) for (\(x), \(z))")
                XCTAssertTrue(p.y > 0 && p.y < size.height, "y \(p.y) for (\(x), \(z))")
            }
        }
    }

    func testFarEndAppearsHigherAndSmallerThanNearEnd() {
        let camera = CourtCamera()
        let size = CGSize(width: 390, height: 844)
        let near = camera.project(Vec3(-1.37, 0, 0), in: size)!
        let far = camera.project(Vec3(1.37, 0, 0), in: size)!
        XCTAssertLessThan(far.y, near.y)
        XCTAssertLessThan(camera.scale(at: Vec3(1.37, 0, 0), in: size), camera.scale(at: Vec3(-1.37, 0, 0), in: size))
    }

    func testPointBehindCameraIsNotProjected() {
        XCTAssertNil(CourtCamera().project(Vec3(-6, 1, 0), in: CGSize(width: 390, height: 844)))
    }

    func testEveryStrokeHasPoseThatReturnsToReady() {
        for stroke in StrokeKind.allCases {
            let start = PaddleChoreography.pose(stroke: stroke, side: .forehand, progress: 0, handed: 1)
            let end = PaddleChoreography.pose(stroke: stroke, side: .forehand, progress: 1, handed: 1)
            let ready = PaddleChoreography.ready(handed: 1)
            XCTAssertEqual(start.right, ready.right, accuracy: 1e-9, "\(stroke)")
            XCTAssertEqual(end.right, ready.right, accuracy: 1e-9, "\(stroke)")
        }
    }

    func testPaddleNormalPointsAlongHittersDirection() {
        let pose = PaddleChoreography.ready(handed: 1)
        let human = PaddleGeometry.make(anchor: .zero, pose: pose, facing: .towardFar)
        let opponent = PaddleGeometry.make(anchor: .zero, pose: pose, facing: .towardNear)
        XCTAssertGreaterThan(human.normal.x, 0)
        XCTAssertLessThan(opponent.normal.x, 0)
    }

    func testRouterPushAndReplace() {
        let router = AppRouter()
        router.push(.play)
        router.push(.match(MatchSetup(opponent: 0)))
        XCTAssertEqual(router.path.count, 2)
        router.replaceTop(with: .matchResult)
        XCTAssertEqual(router.path.count, 2)
        router.popToRoot()
        XCTAssertEqual(router.path.count, 0)
    }
}
