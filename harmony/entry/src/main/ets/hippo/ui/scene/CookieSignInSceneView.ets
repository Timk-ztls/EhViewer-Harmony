/*
 * W-017① CookieSignInSceneView —— 按上游 `scene_cookie_sign_in.xml` 重做（10 项逐条对齐）
 *
 * 上一版的真缺陷（真机截图暴露）：**文字几乎不可见** —— 浅色背景 (#FAFAFA) 上沿用默认文字色，
 * 表现为白字白底。对比度问题比布局差异严重一个量级（后者"不好看"，前者"功能不可用"）。
 *
 * 结构对照（上游 → 本文件）：
 *   LinearLayout(padding=keyline_margin=16)                → Column(padding 16)
 *   ImageView v_cookie_brown_x48（居中, padding 16）        → Image($r('app.media.v_cookie_brown_x48')) 48×48 + margin 16
 *     └ ScrollView(paddingTop/Bottom=16, clipToPadding=false) → Column(padding {top:16,bottom:16})
 *        ├ TextView @string/cookie_explain + textColorPrimary + text_little_small
 *        │    → Text($r('app.string.cookie_explain')) 显式深色 + 12fp
 *        └ 3 × TextInputLayout(minWidth=single_max_width, hint = 小写键名)
 *             → 3 × TextInput(宽度约束, hint 原文小写, 显式 fontColor/placeholderColor)
 *   buttonPanel(gravity=bottom)，两个 Button layout_weight=1
 *     左：从剪贴板导入（上游 textColor=colorAccent + bold）
 *     右：@android:string/ok = **"确定"** → $r('app.string.ok')（本次新增）
 *
 * 文案修正（上一版 3 处自造）：
 *   · 标题 `sign_in_via_cookies`（"通过 Cookie 登录"）→ 上游是 `cookie_explain` 的说明文字
 *   · hint `'igneous（可留空）'` → 上游就是 `igneous`（说明交给 explain 文案）
 *   · 右按钮文案：**曾经误用过** `edit_host_confirm`（属"修改主机"场景）→ 现用 `ok`（确定）
 *
 * 资产说明：上游是**矢量** drawable（48dp，pathData=@string/pd_cookie，fillColor=@color/brown_500 #ff795548），
 *   不是位图 —— 因此不适用 convert_media.ps1 的 density 目录映射。已按同一 pathData 生成
 *   `base/media/v_cookie_brown_x48.svg`（矢量，无 density 概念），视图用 Image 加载（:114）。
 *   若将来上游改用位图，再走 convert_media.ps1 的 mdpi→base 等映射。
 *
 * 观测面：getApplyCount() / getLastApplyResult() / getFieldCount()
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CookieSignInScene } from '../../ehviewer/ui/scene/sign/CookieSignInScene';

const DOMAIN: number = 0x0000;
const TAG: string = 'CookieSignInSceneView';
/** 上游 `?android:attr/textColorPrimary`（浅色主题 = 87% 黑），显式给出，避免"白字白底" */
const TEXT_PRIMARY: string = '#DE000000';
/** 上游 `@dimen/keyline_margin` = 16vp */
const KEYLINE: number = 16;
/** 上游 @dimen/single_max_width：base 260dp / sw600dp 480dp（我们 dimens.json 已同值，故直接走资源） */

@Component export struct CookieSignInSceneView {
  scene: CookieSignInScene | null = null;
  @State memberId: string = '';
  @State passHash: string = '';
  @State igneous: string = '';
  @State message: string = '';
  @State messageRes: Resource | null = null;
  @State isSuccessMsg: boolean = false;

  private applyCount: number = 0;
  private lastApplyResult: boolean = false;

  aboutToAppear(): void {
    const s: CookieSignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      // 上游 onCreateView2 尾部：旧 cookie 回填（先回填，再允许用户改）
      s.restoreLegacyCookies();
      this.memberId = s.getIpbMemberId();
      this.passHash = s.getIpbPassHash();
      this.igneous = s.getIgneous();
    } catch (e) {
      this.message = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'restoreLegacyCookies 抛出: %{public}s；后果：字段为空，需手填', this.message);
    }
  }

  getApplyCount(): number { return this.applyCount; }
  getLastApplyResult(): boolean { return this.lastApplyResult; }
  getFieldCount(): number {
    let n: number = 0;
    if (this.memberId.length > 0) { n++; }
    if (this.passHash.length > 0) { n++; }
    if (this.igneous.length > 0) { n++; }
    return n;
  }

  private submit(): void {
    const s: CookieSignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    s.setFields(this.memberId, this.passHash, this.igneous);
    this.applyCount = this.applyCount + 1;
    try {
      const ok: boolean = s.apply();
      this.lastApplyResult = ok;
      // 上游错误提示不是常驻：成功即清空，失败才显示
      this.message = '';
      this.isSuccessMsg = false;
      this.messageRes = ok ? null : $r('app.string.wrong_cookie_warning');
      if (!ok) {
        hilog.warn(DOMAIN, TAG, 'apply 返回 false；后果：未写入 cookie，用户停留在本页');
      }
    } catch (e) {
      this.lastApplyResult = false;
      this.isSuccessMsg = false;
      this.messageRes = null;
      this.message = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'apply 抛出: %{public}s；后果：登录未生效，停留在本页', this.message);
    }
  }

  private importFromClipboard(): void {
    const s: CookieSignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      const found: boolean = s.importCookieFromClipboard();
      this.memberId = s.getIpbMemberId();
      this.passHash = s.getIpbPassHash();
      this.igneous = s.getIgneous();
      this.message = '';
      if (found) {
        this.isSuccessMsg = true;
        this.messageRes = $r('app.string.found_cookies');
      } else {
        this.isSuccessMsg = false;
        this.messageRes = $r('app.string.text_is_empty');
      }
    } catch (e) {
      this.isSuccessMsg = false;
      this.messageRes = null;
      this.message = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'importCookieFromClipboard 抛出: %{public}s；后果：字段未填充', this.message);
    }
  }

  build() {
    // 上游 LinearLayout(vertical, padding=keyline_margin) 包「图标 + 可滚动表单 + 底部按钮栏」
    Column() {
      // ① 顶部插图：上游 @drawable/v_cookie_brown_x48（vector 48dp，fillColor=@color/brown_500 #ff795548）
      //    上游是 vector + pathData=@string/pd_cookie；已按同一 pathData 生成 SVG 放到 base/media/，
      //    ArkUI 直接 Image 加载即可（矢量，无需分 density 目录）。
      Image($r('app.media.v_cookie_brown_x48'))
        .width(48)
        .height(48)
        .objectFit(ImageFit.Contain)
        .margin({ top: KEYLINE, bottom: KEYLINE })
        .alignSelf(ItemAlign.Center)

      // ② 可滚动表单区（上游 MaxSizeContainer(weight=1) + ScrollView）
      Scroll() {
        Column({ space: 12 }) {
          // ③ 说明文字：上游 cookie_explain + textColorPrimary + text_little_small
          Text($r('app.string.cookie_explain'))
            .fontSize(12)
            .fontColor(TEXT_PRIMARY)
            .width('100%')

          // ④ 三个输入框：hint 就是小写键名本身；宽度受 single_max_width 约束
          TextInput({ placeholder: 'ipb_member_id', text: this.memberId })
            .onChange((v: string) => { this.memberId = v; })
            .fontColor(TEXT_PRIMARY)
            .placeholderColor('#99000000')
            .constraintSize({ maxWidth: $r('app.float.single_max_width') })
            .width('100%')

          TextInput({ placeholder: 'ipb_pass_hash', text: this.passHash })
            .onChange((v: string) => { this.passHash = v; })
            .fontColor(TEXT_PRIMARY)
            .placeholderColor('#99000000')
            .constraintSize({ maxWidth: $r('app.float.single_max_width') })
            .width('100%')

          TextInput({ placeholder: 'igneous', text: this.igneous })
            .onChange((v: string) => { this.igneous = v; })
            .fontColor(TEXT_PRIMARY)
            .placeholderColor('#99000000')
            .constraintSize({ maxWidth: $r('app.float.single_max_width') })
            .width('100%')

          // ⑤ 错误/成功提示：上游不是常驻（成功即清空或显示发现 cookie）
          if (this.messageRes !== null || this.message.length > 0) {
            Text(this.messageRes !== null ? this.messageRes : this.message)
              .fontSize(12)
              .fontColor(this.isSuccessMsg ? $r('app.color.colorAccent') : '#C62828')
              .width('100%')
          }
        }
        .width('100%')
        .padding({ top: KEYLINE, bottom: KEYLINE })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .width('100%')

      // ⑥ 底部按钮栏：上游 buttonPanel(gravity=bottom)，两按钮 layout_weight=1 平分
      Row({ space: 12 }) {
        // 左：从剪贴板导入（上游 textColor=colorAccent + bold）
        Button($r('app.string.cookie_login_import_in_clipboard'))
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.colorAccent'))
          .fontWeight(FontWeight.Bold)
          .onClick(() => { this.importFromClipboard(); })
        // 右：确定（上游 @android:string/ok = "确定"；textColor=colorPrimary + bold）
        Button($r('app.string.ok'))
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.colorPrimary'))
          .fontWeight(FontWeight.Bold)
          .onClick(() => { this.submit(); })
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(KEYLINE)
    .backgroundColor($r('app.color.background_light'))
  }
}
