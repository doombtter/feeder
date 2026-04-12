import Flutter
import UIKit
import FirebaseAuth

class SceneDelegate: FlutterSceneDelegate {
    
    // URL 콜백 처리 추가
    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for urlContext in URLContexts {
            let url = urlContext.url
            if Auth.auth().canHandle(url) {
                return
            }
        }
        super.scene(scene, openURLContexts: URLContexts)
    }
}