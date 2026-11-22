/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/preference/SignInRequiredActivityPreference.java（S0172，上游 69 行）
 *
 * 判据：**UI 组件行**（`extends ActivityPreference`），自有逻辑只有 `onClick()`：
 *   取 EhCookieStore + EhUrl.HOST_E 的 cookie → **未登录则不跳转**（上游在 onClick 里判登录态），
 *   已登录才走基类的活动跳转。
 *   （`onBindViewHolder` 只是缓存 itemView，ArkUI 无对位，不移植。）
 *
 * ⇒ 组合 `ActivityPreference` + 登录态判定注入（EhCookieStore 属 core-runtime）。
 * 断言重点：未登录时**不**触发 onLaunch（防止"点了没反应"被误判为接线错误）。
 */
import { ActivityPreference } from '../../preference/ActivityPreference';

@Component
export struct SignInRequiredActivityPreference {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop routeKey: string = '';
  /** 登录态判定（core-runtime 的 EhCookieStore 等价物） */
  isSignedIn: () => boolean = () => false;
  onLaunch: (routeKey: string) => void = (routeKey: string) => {
  };
  /** 未登录时的提示（上游不跳转，由调用方决定提示方式） */
  onRequireSignIn: () => void = () => {
  };

  build() {
    ActivityPreference({
      title: this.title,
      summary: this.summary,
      routeKey: this.routeKey,
      onLaunch: (key: string) => {
        if (this.isSignedIn()) {
          this.onLaunch(key);
        } else {
          this.onRequireSignIn();
        }
      }
    })
  }
}
