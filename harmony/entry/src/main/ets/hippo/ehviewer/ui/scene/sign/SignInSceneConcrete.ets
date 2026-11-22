/*
 * U-02b：`SignInScene` 的薄子类。默认注入 `UnavailableSignInClient`。
 */
import { SignInScene } from './SignInScene';
import { UnavailableSignInClient } from './SignInScene';

export class SignInSceneConcrete extends SignInScene {
  constructor() {
    super();
    this.setSignInClient(new UnavailableSignInClient());
  }

  getSceneName(): string {
    return 'SignInScene';
  }
}
