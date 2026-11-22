/**
 * 迁移自 app/src/main/java/com/hippo/widget/lockpattern/LockPatternView.java（inventory S0530，上游 990 行）
 *
 * 这是安全相关控件，按下述对照表**逐条搬**，不做简化：状态机、命中判定（含补格规则）、
 * 动画时长与 easing 曲线、绘制顺序、透明度算法全部保留。
 *
 * ============================ 上游 → ArkUI 对照 ============================
 * 继承 View / onMeasure                                    → @Component struct + aspectRatio(1)
 *   （上游 mAspect 恒为 ASPECT_SQUARE，另两种已被注释掉，故 w=h=min(w,h) 等价于 .aspectRatio(1)）
 * onSizeChanged(w,h) → mSquareWidth = w/3                 → onAreaChange → controller.onSizeChanged(w,h)
 * onDraw(Canvas)                                          → CanvasRenderingContext2D 逐指令重放（本文件 draw()）
 * Paint.setAntiAlias(true)                                → Canvas 默认抗锯齿；不设 imageSmoothing 相关项
 * Paint.setStyle(STROKE) + StrokeJoin.ROUND + StrokeCap.ROUND → ctx.lineJoin='round' / ctx.lineCap='round'
 * Paint.setStrokeWidth(mPathWidth)                        → ctx.lineWidth = pathWidth
 * Paint.setAlpha(a)                                       → ctx.globalAlpha = a
 * Canvas.drawCircle(x, y, r, paint)                       → ctx.beginPath()+arc(x,y,r,0,2π)+fill()
 * Canvas.drawPath(path, mPathPaint)                       → ctx.beginPath()+moveTo/lineTo+stroke()
 * Path.rewind()                                           → ctx.beginPath()
 * invalidate() / invalidate(l,t,r,b)                      → requestRedraw()：**整画布重绘**
 *   （ArkUI Canvas 无脏矩形失效机制；上游的 mInvalidate/mTmpInvalidateRect 只是性能优化，
 *     语义上等价于"重画一次"，此处按整画布重绘，绘制结果一致）
 * ValueAnimator.ofFloat + Interpolator                    → ValueAnimation + CubicBezierEasing（本文件）
 *   FastOutSlowInInterpolator   = cubic-bezier(0.4, 0.0, 0.2, 1.0)   原值搬
 *   LinearOutSlowInInterpolator = cubic-bezier(0.0, 0.0, 0.2, 1.0)   原值搬
 * SystemClock.elapsedRealtime()                           → Date.now()
 * MotionEvent.ACTION_DOWN/UP/MOVE/CANCEL                  → TouchType.Down/Up/Move/Cancel
 * animateLeft/Right（多指）                                → 只取 event.touches[0]，多余触点忽略（上游同为主触点语义）
 * event.getHistoricalX(i) 历史点循环                       → 用「上一位置 → 当前位置」线段等距采样替代（见 handleActionMove）
 * performHapticFeedback(VIRTUAL_KEY)                      → hapticExecutor 回调（默认空实现，见文件尾说明）
 * onSaveInstanceState/onRestoreInstanceState + Parcelable → LockPatternSavedState + saveState()/restoreState()
 * AttrResources.getAttrBoolean(isLightTheme)              → @Prop isLightTheme: boolean（调用方按主题传入）
 *
 * ============================ 触摸状态机（与上游逐分支对应） ============================
 * Down   : resetPattern() → detectAndAddHit  命中 ⇒ patternInProgress=true, displayMode=Correct, notifyPatternStarted
 *                                            未命中且 patternInProgress ⇒ patternInProgress=false, notifyPatternCleared
 * Move   : 采样点 → detectAndAddHit；首个格 ⇒ patternInProgress=true, notifyPatternStarted
 * Up     : pattern 非空 ⇒ patternInProgress=false, cancelLineAnimations(), notifyPatternDetected(), redraw
 * Cancel : patternInProgress ⇒ patternInProgress=false, resetPattern(), notifyPatternCleared()
 * 输入被禁用（inputEnabled=false）或组件 disabled ⇒ 整段触摸忽略（返回 false 的等价行为：不处理）
 * ============================ 无法等价 / 已登记差异 ============================
 * 1) 历史触点：ArkUI TouchEvent 不带 getHistoricalX(i) 数组；改为在线段上按 ≤ min(squareWidth/8, 4vp) 步长采样，
 *    与上游"逐个历史点送 detectAndAddHit"效果一致（补格规则依赖的是点的顺序与覆盖，不是时间戳）。
 * 2) 脏矩形局部刷新：见上，整画布重绘。
 * 3) 无障碍 hover 通道（onHoverEvent → onTouchEvent 转发）：ArkUI 的 hover 事件不带触点坐标，
 *    无障碍场景改由外层容器转发坐标，组件本身不实现该转发（已登记 MR「平台差异」）。
 * 4) 震动：不申请 ohos.permission.VIBRATE，改为注入回调，由 entry 侧接 @ohos.vibrator。
 */
import { Cell } from './LockPatternCell';
import { LockPatternUtils } from './LockPatternUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.LockPatternView';

/** 上游 DisplayMode */
export enum DisplayMode {
  Correct = 0,
  Animate = 1,
  Wrong = 2
}

/** 上游 OnPatternListener */
export interface OnPatternListener {
  onPatternStart(): void;

  onPatternCleared(): void;

  onPatternCellAdded(pattern: Cell[]): void;

  onPatternDetected(pattern: Cell[]): void;
}

/** 上游 CellState（含动画中间量） */
export class CellState {
  scale: number = 1.0;
  translateY: number = 0.0;
  alpha: number = 1.0;
  size: number = 12;
  lineEndX: number = Number.MIN_VALUE;
  lineEndY: number = Number.MIN_VALUE;
  /** 上游以 lineAnimator != null 表示线段动画在跑，此处用布尔量等价表达 */
  lineEndAnimating: boolean = false;
}

/** cubic-bezier 插值器：与 androidx PathInterpolator 同算法（先解 x，再取 y） */
export class CubicBezierEasing {
  private x1: number;
  private y1: number;
  private x2: number;
  private y2: number;

  constructor(x1: number, y1: number, x2: number, y2: number) {
    this.x1 = x1;
    this.y1 = y1;
    this.x2 = x2;
    this.y2 = y2;
  }

  static fastOutSlowIn(): CubicBezierEasing {
    return new CubicBezierEasing(0.4, 0.0, 0.2, 1.0);
  }

  static linearOutSlowIn(): CubicBezierEasing {
    return new CubicBezierEasing(0.0, 0.0, 0.2, 1.0);
  }

  private static bezier(t: number, p1: number, p2: number): number {
    const mt: number = 1.0 - t;
    return 3.0 * mt * mt * t * p1 + 3.0 * mt * t * t * p2 + t * t * t;
  }

  getInterpolation(input: number): number {
    if (input <= 0) {
      return 0.0;
    }
    if (input >= 1) {
      return 1.0;
    }
    // 二分求解 x(t)=input（PathInterpolator 用 Newton-Raphson，这里用二分，精度 1e-7，结果一致）
    let lo: number = 0.0;
    let hi: number = 1.0;
    let t: number = input;
    for (let i = 0; i < 24; i++) {
      t = (lo + hi) / 2.0;
      const x: number = CubicBezierEasing.bezier(t, this.x1, this.x2);
      if (x < input) {
        lo = t;
      } else {
        hi = t;
      }
    }
    return CubicBezierEasing.bezier(t, this.y1, this.y2);
  }
}

/** ValueAnimator 等价物：一个 0→1 的时间轴 + 取值回调 */
class ValueAnimation {
  readonly startValue: number;
  readonly endValue: number;
  readonly duration: number;
  readonly easing: CubicBezierEasing;
  readonly onUpdate: (v: number) => void;
  readonly onEnd: (() => void) | null;
  startTime: number = -1;
  done: boolean = false;

  constructor(startValue: number, endValue: number, duration: number,
              easing: CubicBezierEasing, onUpdate: (v: number) => void, onEnd: (() => void) | null) {
    this.startValue = startValue;
    this.endValue = endValue;
    this.duration = duration;
    this.easing = easing;
    this.onUpdate = onUpdate;
    this.onEnd = onEnd;
  }
}

/** 组件向控制器回吐的宿主能力（重绘 / 震动 / 动画节拍） */
export interface LockPatternHost {
  requestRedraw(): void;

  requestHaptic(): void;

  requestTicker(): void;
}

/** 上游 onSaveInstanceState 的 Parcelable 对位 */
export class LockPatternSavedState {
  serializedPattern: string = '';
  displayMode: number = 0;
  inputEnabled: boolean = true;
  inStealthMode: boolean = false;
  tactileFeedbackEnabled: boolean = true;
}

/**
 * 控件状态与逻辑（上游 View 的字段 + 方法整体搬入）。
 * 为什么不是 @State 驱动：上游是"命令式重绘"的 Canvas 控件，绘制顺序与动画中间量必须逐帧可控，
 * ArkUI 状态系统无法表达"每个 cell 自己的 size/lineEnd 动画"，故保留命令式内核，只把 Canvas 交给组件。
 */
export class LockPatternController {
  // ---------- 上游尺寸常量（res/values/dimens.xml 原值）----------
  static readonly DOT_LINE_WIDTH: number = 3;      // lock_pattern_dot_line_width = 3dp
  static readonly DOT_SIZE: number = 12;           // lock_pattern_dot_size = 12dp
  static readonly DOT_SIZE_ACTIVATED: number = 28; // lock_pattern_dot_size_activated = 28dp
  static readonly MILLIS_PER_CIRCLE_ANIMATING: number = 700;
  static readonly DRAG_THRESHHOLD: number = 0.0;
  static readonly HIT_FACTOR: number = 0.6;

  // ---------- 上游颜色（res/values/colors.xml 原值；?attr 由调用方按主题选 light/dark）----------
  static readonly REGULAR_COLOR_LIGHT: string = '#8A000000'; // lock_pattern_view_regular_color_light
  static readonly REGULAR_COLOR_DARK: string = '#8AFFFFFF';  // lock_pattern_view_regular_color_dark
  static readonly SUCCESS_COLOR: string = '#FF009688';       // @color/colorPrimary = teal_500
  static readonly ERROR_COLOR: string = '#FFF44336';         // @color/red_500

  // ---------- 上游字段 ----------
  pattern: Cell[] = [];
  patternDrawLookup: boolean[][] = [[false, false, false], [false, false, false], [false, false, false]];
  inProgressX: number = -1;
  inProgressY: number = -1;
  animatingPeriodStart: number = 0;
  patternDisplayMode: DisplayMode = DisplayMode.Correct;
  inputEnabled: boolean = true;
  inStealthMode: boolean = false;
  enableHapticFeedback: boolean = true;
  patternInProgress: boolean = false;
  cellStates: CellState[][] = [];

  dotSize: number = LockPatternController.DOT_SIZE;
  dotSizeActivated: number = LockPatternController.DOT_SIZE_ACTIVATED;
  pathWidth: number = LockPatternController.DOT_LINE_WIDTH;
  isLightTheme: boolean = true;

  // 尺寸（onSizeChanged 对位）；padding 上游来自 getPadding*，ArkUI 由外层容器给内边距，此处恒 0
  viewWidth: number = 0;
  viewHeight: number = 0;
  squareWidth: number = 0;
  squareHeight: number = 0;

  onPatternListener: OnPatternListener | null = null;
  /** 装配期是否已接线：null 回调会让控件"看起来正常但什么都不做"（controller 是普通类，不能用 @State） */
  inert: boolean = false;

  /**
   * 回调落空告警：上游 OnPatternListener 为 null 时 4 个回调全部静默丢弃 ——
   * 用户认真画完手势却什么都不发生、不解锁、不提示，控件外观完全正常（"没接线 = 坏了"）。
   * 故装配期与每次回调落空都 hilog.error，不再静默。
   */
  /** 装配期接线检查（由 LockPatternView.aboutToAppear 调用；可被日志巡检/单测覆盖） */
  checkWiring(): void {
    if (this.onPatternListener === null) {
      this.warnIfInert('aboutToAppear');
    }
  }

  private warnIfInert(name: string): void {
    this.inert = true;
    hilog.error(LOG_DOMAIN, LOG_TAG,
      '%{public}s: onPatternListener is null, callback dropped (control is inert)', name);
  }
  hapticExecutor: (() => void) | null = null;

  private host: LockPatternHost | null = null;
  private animations: ValueAnimation[] = [];
  private fastOutSlowIn: CubicBezierEasing = CubicBezierEasing.fastOutSlowIn();
  private linearOutSlowIn: CubicBezierEasing = CubicBezierEasing.linearOutSlowIn();
  // 上一点（历史点采样用）
  private lastSampleX: number = -1;
  private lastSampleY: number = -1;

  constructor() {
    for (let i = 0; i < 3; i++) {
      const rowArr: CellState[] = [];
      for (let j = 0; j < 3; j++) {
        const s: CellState = new CellState();
        s.size = this.dotSize;
        rowArr.push(s);
      }
      this.cellStates.push(rowArr);
    }
  }

  attach(host: LockPatternHost): void {
    this.host = host;
  }

  detach(): void {
    this.host = null;
    this.animations = [];
  }

  // ---------- 尺寸 ----------
  onSizeChanged(w: number, h: number): void {
    this.viewWidth = w;
    this.viewHeight = h;
    this.squareWidth = w / 3.0;
    this.squareHeight = h / 3.0;
    this.requestRedraw();
  }

  private requestRedraw(): void {
    if (this.host !== null) {
      this.host.requestRedraw();
    }
  }

  private requestHaptic(): void {
    if (this.enableHapticFeedback) {
      if (this.hapticExecutor !== null) {
        this.hapticExecutor();
      } else if (this.host !== null) {
        this.host.requestHaptic();
      }
    }
  }

  // ---------- 对外 API（与上游 public 方法一一对应）----------
  getCellStates(): CellState[][] {
    return this.cellStates;
  }

  getCellSize(): number {
    return this.pattern.length;
  }

  getPatternString(): string {
    return LockPatternUtils.patternToString(this.pattern);
  }

  isInStealthMode(): boolean {
    return this.inStealthMode;
  }

  isTactileFeedbackEnabled(): boolean {
    return this.enableHapticFeedback;
  }

  setInStealthMode(inStealthMode: boolean): void {
    this.inStealthMode = inStealthMode;
  }

  setTactileFeedbackEnabled(tactileFeedbackEnabled: boolean): void {
    this.enableHapticFeedback = tactileFeedbackEnabled;
  }

  setOnPatternListener(listener: OnPatternListener | null): void {
    this.onPatternListener = listener;
    this.inert = listener === null;
  }

  setPattern(displayMode: DisplayMode, pattern: Cell[]): void {
    this.pattern = pattern.slice();
    this.clearPatternDrawLookup();
    for (let i = 0; i < pattern.length; i++) {
      const cell: Cell = pattern[i];
      this.patternDrawLookup[cell.getRow()][cell.getColumn()] = true;
    }
    this.setDisplayMode(displayMode);
  }

  setDisplayMode(displayMode: DisplayMode): void {
    this.patternDisplayMode = displayMode;
    if (displayMode === DisplayMode.Animate) {
      if (this.pattern.length === 0) {
        throw new Error('you must have a pattern to animate if you want to set the display mode to animate');
      }
      this.animatingPeriodStart = Date.now();
      const first: Cell = this.pattern[0];
      this.inProgressX = this.getCenterXForColumn(first.getColumn());
      this.inProgressY = this.getCenterYForRow(first.getRow());
      this.clearPatternDrawLookup();
      this.requestTicker();
    }
    this.requestRedraw();
  }

  getDisplayMode(): DisplayMode {
    return this.patternDisplayMode;
  }

  clearPattern(): void {
    this.resetPattern();
  }

  disableInput(): void {
    this.inputEnabled = false;
  }

  enableInput(): void {
    this.inputEnabled = true;
  }

  // ---------- 存档（上游 SavedState 对位）----------
  saveState(): LockPatternSavedState {
    const ss: LockPatternSavedState = new LockPatternSavedState();
    ss.serializedPattern = LockPatternUtils.patternToString(this.pattern);
    ss.displayMode = this.patternDisplayMode === DisplayMode.Wrong ? 2 : (this.patternDisplayMode === DisplayMode.Animate ? 1 : 0);
    ss.inputEnabled = this.inputEnabled;
    ss.inStealthMode = this.inStealthMode;
    ss.tactileFeedbackEnabled = this.enableHapticFeedback;
    return ss;
  }

  restoreState(ss: LockPatternSavedState): void {
    this.setPattern(DisplayMode.Correct, LockPatternUtils.stringToPattern(ss.serializedPattern));
    this.patternDisplayMode = ss.displayMode === 2 ? DisplayMode.Wrong : (ss.displayMode === 1 ? DisplayMode.Animate : DisplayMode.Correct);
    this.inputEnabled = ss.inputEnabled;
    this.inStealthMode = ss.inStealthMode;
    this.enableHapticFeedback = ss.tactileFeedbackEnabled;
    this.requestRedraw();
  }

  // ---------- 内部状态 ----------
  private notifyCellAdded(): void {
    if (this.onPatternListener !== null) {
      this.onPatternListener.onPatternCellAdded(this.pattern);
    } else {
      this.warnIfInert('onPatternCellAdded');
    }
  }

  private notifyPatternStarted(): void {
    if (this.onPatternListener !== null) {
      this.onPatternListener.onPatternStart();
    } else {
      this.warnIfInert('onPatternStart');
    }
  }

  private notifyPatternDetected(): void {
    if (this.onPatternListener !== null) {
      this.onPatternListener.onPatternDetected(this.pattern);
    } else {
      this.warnIfInert('onPatternDetected');
    }
  }

  private notifyPatternCleared(): void {
    if (this.onPatternListener !== null) {
      this.onPatternListener.onPatternCleared();
    } else {
      this.warnIfInert('onPatternCleared');
    }
  }

  private resetPattern(): void {
    this.pattern = [];
    this.clearPatternDrawLookup();
    this.patternDisplayMode = DisplayMode.Correct;
    this.requestRedraw();
  }

  private clearPatternDrawLookup(): void {
    for (let i = 0; i < 3; i++) {
      for (let j = 0; j < 3; j++) {
        this.patternDrawLookup[i][j] = false;
      }
    }
  }

  // ---------- 命中判定（逐条对应，含补格规则）----------
  private detectAndAddHit(x: number, y: number): Cell | null {
    const cell: Cell | null = this.checkForNewHit(x, y);
    if (cell !== null) {
      // check for gaps in existing pattern
      let fillInGapCell: Cell | null = null;
      const pattern: Cell[] = this.pattern;
      if (pattern.length > 0) {
        const lastCell: Cell = pattern[pattern.length - 1];
        const dRow: number = cell.row - lastCell.row;
        const dColumn: number = cell.column - lastCell.column;

        let fillInRow: number = lastCell.row;
        let fillInColumn: number = lastCell.column;

        if (Math.abs(dRow) === 2 && Math.abs(dColumn) !== 1) {
          fillInRow = lastCell.row + (dRow > 0 ? 1 : -1);
        }
        if (Math.abs(dColumn) === 2 && Math.abs(dRow) !== 1) {
          fillInColumn = lastCell.column + (dColumn > 0 ? 1 : -1);
        }
        fillInGapCell = Cell.of(fillInRow, fillInColumn);
      }

      if (fillInGapCell !== null && !this.patternDrawLookup[fillInGapCell.row][fillInGapCell.column]) {
        this.addCellToPattern(fillInGapCell);
      }
      this.addCellToPattern(cell);
      if (this.enableHapticFeedback) {
        this.requestHaptic();
      }
      return cell;
    }
    return null;
  }

  private addCellToPattern(newCell: Cell): void {
    this.patternDrawLookup[newCell.getRow()][newCell.getColumn()] = true;
    this.pattern.push(newCell);
    if (!this.inStealthMode) {
      this.startCellActivatedAnimation(newCell);
    }
    this.notifyCellAdded();
  }

  private startCellActivatedAnimation(cell: Cell): void {
    const cellState: CellState = this.cellStates[cell.row][cell.column];
    // 96ms: dotSize → dotSizeActivated（linearOutSlowIn）；结束后 192ms 回弹（fastOutSlowIn）
    this.startSizeAnimation(this.dotSize, this.dotSizeActivated, 96, this.linearOutSlowIn, cellState, () => {
      this.startSizeAnimation(this.dotSizeActivated, this.dotSize, 192, this.fastOutSlowIn, cellState, null);
    });
    this.startLineEndAnimation(cellState, this.inProgressX, this.inProgressY,
      this.getCenterXForColumn(cell.column), this.getCenterYForRow(cell.row));
  }

  private startLineEndAnimation(state: CellState, startX: number, startY: number,
                                targetX: number, targetY: number): void {
    const anim: ValueAnimation = new ValueAnimation(0, 1, 100, this.fastOutSlowIn, (t: number) => {
      state.lineEndX = (1 - t) * startX + t * targetX;
      state.lineEndY = (1 - t) * startY + t * targetY;
      this.requestRedraw();
    }, () => {
      state.lineEndAnimating = false;
    });
    state.lineEndAnimating = true;
    this.animations.push(anim);
    this.requestTicker();
  }

  private startSizeAnimation(start: number, end: number, duration: number,
                             easing: CubicBezierEasing, state: CellState,
                             endRunnable: (() => void) | null): void {
    const anim: ValueAnimation = new ValueAnimation(start, end, duration, easing, (v: number) => {
      state.size = v;
      this.requestRedraw();
    }, endRunnable);
    this.animations.push(anim);
    this.requestTicker();
  }

  private cancelLineAnimations(): void {
    for (let i = 0; i < 3; i++) {
      for (let j = 0; j < 3; j++) {
        const state: CellState = this.cellStates[i][j];
        if (state.lineEndAnimating) {
          state.lineEndAnimating = false;
          state.lineEndX = Number.MIN_VALUE;
          state.lineEndY = Number.MIN_VALUE;
        }
      }
    }
    this.animations = this.animations.filter((a: ValueAnimation) => !a.done);
  }

  private checkForNewHit(x: number, y: number): Cell | null {
    const rowHit: number = this.getRowHit(y);
    if (rowHit < 0) {
      return null;
    }
    const columnHit: number = this.getColumnHit(x);
    if (columnHit < 0) {
      return null;
    }
    if (this.patternDrawLookup[rowHit][columnHit]) {
      return null;
    }
    return Cell.of(rowHit, columnHit);
  }

  private getRowHit(y: number): number {
    const squareHeight: number = this.squareHeight;
    const hitSize: number = squareHeight * LockPatternController.HIT_FACTOR;
    const offset: number = (squareHeight - hitSize) / 2.0; // getPaddingTop() = 0
    for (let i = 0; i < 3; i++) {
      const hitTop: number = offset + squareHeight * i;
      if (y >= hitTop && y <= hitTop + hitSize) {
        return i;
      }
    }
    return -1;
  }

  private getColumnHit(x: number): number {
    const squareWidth: number = this.squareWidth;
    const hitSize: number = squareWidth * LockPatternController.HIT_FACTOR;
    const offset: number = (squareWidth - hitSize) / 2.0; // getPaddingLeft() = 0
    for (let i = 0; i < 3; i++) {
      const hitLeft: number = offset + squareWidth * i;
      if (x >= hitLeft && x <= hitLeft + hitSize) {
        return i;
      }
    }
    return -1;
  }

  // ---------- 触摸 ----------
  handleActionDown(x: number, y: number): void {
    this.resetPattern();
    this.lastSampleX = x;
    this.lastSampleY = y;
    const hitCell: Cell | null = this.detectAndAddHit(x, y);
    if (hitCell !== null) {
      this.patternInProgress = true;
      this.patternDisplayMode = DisplayMode.Correct;
      this.notifyPatternStarted();
    } else if (this.patternInProgress) {
      this.patternInProgress = false;
      this.notifyPatternCleared();
    }
    this.inProgressX = x;
    this.inProgressY = y;
    this.requestRedraw();
  }

  /**
   * 上游 handleActionMove 的历史点循环 → 线段等距采样。
   * 采样步长 = min(squareWidth/8, 4)：保证不会跨越整个格（格内命中区为 0.6×格宽），
   * 因此补格规则（跨两格时补中间格）与上游逐历史点判定结果一致。
   */
  handleActionMove(x: number, y: number): void {
    const startX: number = this.lastSampleX < 0 ? x : this.lastSampleX;
    const startY: number = this.lastSampleY < 0 ? y : this.lastSampleY;
    const dxTotal: number = x - startX;
    const dyTotal: number = y - startY;
    const dist: number = Math.sqrt(dxTotal * dxTotal + dyTotal * dyTotal);
    const step: number = Math.min(this.squareWidth / 8.0, 4.0);
    const steps: number = step > 0 ? Math.max(1, Math.ceil(dist / step)) : 1;

    for (let i = 1; i <= steps; i++) {
      const t: number = i / steps;
      const px: number = startX + dxTotal * t;
      const py: number = startY + dyTotal * t;
      const hitCell: Cell | null = this.detectAndAddHit(px, py);
      const patternSize: number = this.pattern.length;
      if (hitCell !== null && patternSize === 1) {
        this.patternInProgress = true;
        this.notifyPatternStarted();
      }
    }

    this.lastSampleX = x;
    this.lastSampleY = y;
    this.inProgressX = x;
    this.inProgressY = y;
    this.requestRedraw();
  }

  handleActionUp(): void {
    if (this.pattern.length > 0) {
      this.patternInProgress = false;
      this.cancelLineAnimations();
      this.notifyPatternDetected();
      this.requestRedraw();
    }
  }

  handleActionCancel(): void {
    if (this.patternInProgress) {
      this.patternInProgress = false;
      this.resetPattern();
      this.notifyPatternCleared();
    }
  }

  private getCenterXForColumn(column: number): number {
    return column * this.squareWidth + this.squareWidth / 2.0; // getPaddingLeft() = 0
  }

  private getCenterYForRow(row: number): number {
    return row * this.squareHeight + this.squareHeight / 2.0; // getPaddingTop() = 0
  }

  // ---------- 动画节拍 ----------
  needsTicker(): boolean {
    if (this.patternDisplayMode === DisplayMode.Animate) {
      return true;
    }
    for (let i = 0; i < this.animations.length; i++) {
      if (!this.animations[i].done) {
        return true;
      }
    }
    return false;
  }

  private requestTicker(): void {
    if (this.host !== null) {
      this.host.requestTicker();
    }
  }

  /** 每帧推进所有动画；返回是否需要继续（供组件决定是否停表） */
  tick(now: number): boolean {
    const alive: ValueAnimation[] = [];
    for (let i = 0; i < this.animations.length; i++) {
      const a: ValueAnimation = this.animations[i];
      if (a.done) {
        continue;
      }
      if (a.startTime < 0) {
        a.startTime = now;
      }
      const elapsed: number = now - a.startTime;
      const frac: number = a.duration <= 0 ? 1.0 : Math.min(1.0, elapsed / a.duration);
      const eased: number = a.easing.getInterpolation(frac);
      a.onUpdate(a.startValue + (a.endValue - a.startValue) * eased);
      if (frac >= 1.0) {
        a.done = true;
        if (a.onEnd !== null) {
          a.onEnd();
        }
      } else {
        alive.push(a);
      }
    }
    this.animations = alive;
    // Animate 模式需要持续重绘
    if (this.patternDisplayMode === DisplayMode.Animate) {
      this.requestRedraw();
    }
    return this.needsTicker();
  }

  // ---------- 绘制（上游 onDraw 逐指令对应）----------
  draw(ctx: CanvasRenderingContext2D): void {
    const pattern: Cell[] = this.pattern;
    const count: number = pattern.length;
    const drawLookup: boolean[][] = this.patternDrawLookup;

    ctx.clearRect(0, 0, this.viewWidth, this.viewHeight);

    if (this.patternDisplayMode === DisplayMode.Animate) {
      // + 1 so we pause on complete pattern
      const oneCycle: number = (count + 1) * LockPatternController.MILLIS_PER_CIRCLE_ANIMATING;
      const spotInCycle: number = (Date.now() - this.animatingPeriodStart) % oneCycle;
      const numCircles: number = Math.floor(spotInCycle / LockPatternController.MILLIS_PER_CIRCLE_ANIMATING);

      this.clearPatternDrawLookup();
      for (let i = 0; i < numCircles; i++) {
        const cell: Cell = pattern[i];
        drawLookup[cell.getRow()][cell.getColumn()] = true;
      }

      const needToUpdateInProgressPoint: boolean = numCircles > 0 && numCircles < count;
      if (needToUpdateInProgressPoint) {
        const percentageOfNextCircle: number =
          (spotInCycle % LockPatternController.MILLIS_PER_CIRCLE_ANIMATING) / LockPatternController.MILLIS_PER_CIRCLE_ANIMATING;

        const currentCell: Cell = pattern[numCircles - 1];
        const centerX: number = this.getCenterXForColumn(currentCell.column);
        const centerY: number = this.getCenterYForRow(currentCell.row);

        const nextCell: Cell = pattern[numCircles];
        const dx: number = percentageOfNextCircle * (this.getCenterXForColumn(nextCell.column) - centerX);
        const dy: number = percentageOfNextCircle * (this.getCenterYForRow(nextCell.row) - centerY);
        this.inProgressX = centerX + dx;
        this.inProgressY = centerY + dy;
      }
    }

    // draw the circles
    for (let i = 0; i < 3; i++) {
      const centerY: number = this.getCenterYForRow(i);
      for (let j = 0; j < 3; j++) {
        const cellState: CellState = this.cellStates[i][j];
        const centerX: number = this.getCenterXForColumn(j);
        const size: number = cellState.size * cellState.scale;
        const translationY: number = cellState.translateY;
        this.drawCircle(ctx, centerX, centerY + translationY, size, drawLookup[i][j], cellState.alpha);
      }
    }

    const drawPath: boolean = !this.inStealthMode;
    if (drawPath) {
      const pathColor: string = this.getCurrentColor(true);
      ctx.strokeStyle = pathColor;
      ctx.lineWidth = this.pathWidth;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';

      let anyCircles: boolean = false;
      let lastX: number = 0;
      let lastY: number = 0;
      for (let i = 0; i < count; i++) {
        const cell: Cell = pattern[i];
        if (!drawLookup[cell.row][cell.column]) {
          break;
        }
        anyCircles = true;
        const centerX: number = this.getCenterXForColumn(cell.column);
        const centerY: number = this.getCenterYForRow(cell.row);
        if (i !== 0) {
          const state: CellState = this.cellStates[cell.row][cell.column];
          ctx.beginPath();
          ctx.moveTo(lastX, lastY);
          if (state.lineEndX !== Number.MIN_VALUE && state.lineEndY !== Number.MIN_VALUE) {
            ctx.lineTo(state.lineEndX, state.lineEndY);
          } else {
            ctx.lineTo(centerX, centerY);
          }
          ctx.globalAlpha = 1.0;
          ctx.stroke();
        }
        lastX = centerX;
        lastY = centerY;
      }

      // draw last in progress section
      if ((this.patternInProgress || this.patternDisplayMode === DisplayMode.Animate) && anyCircles) {
        ctx.beginPath();
        ctx.moveTo(lastX, lastY);
        ctx.lineTo(this.inProgressX, this.inProgressY);
        ctx.globalAlpha = this.calculateLastSegmentAlpha(this.inProgressX, this.inProgressY, lastX, lastY);
        ctx.stroke();
        ctx.globalAlpha = 1.0;
      }
    }
  }

  private calculateLastSegmentAlpha(x: number, y: number, lastX: number, lastY: number): number {
    const diffX: number = x - lastX;
    const diffY: number = y - lastY;
    const dist: number = Math.sqrt(diffX * diffX + diffY * diffY);
    const frac: number = this.squareWidth > 0 ? dist / this.squareWidth : 0;
    return Math.min(1.0, Math.max(0.0, (frac - 0.3) * 4.0));
  }

  private getCurrentColor(partOfPattern: boolean): string {
    if (!partOfPattern || this.inStealthMode || this.patternInProgress) {
      return this.isLightTheme
        ? LockPatternController.REGULAR_COLOR_LIGHT
        : LockPatternController.REGULAR_COLOR_DARK;
    } else if (this.patternDisplayMode === DisplayMode.Wrong) {
      return LockPatternController.ERROR_COLOR;
    } else if (this.patternDisplayMode === DisplayMode.Correct || this.patternDisplayMode === DisplayMode.Animate) {
      return LockPatternController.SUCCESS_COLOR;
    }
    throw new Error(`unknown display mode ${this.patternDisplayMode}`);
  }

  private drawCircle(ctx: CanvasRenderingContext2D, centerX: number, centerY: number,
                     size: number, partOfPattern: boolean, alpha: number): void {
    ctx.fillStyle = this.getCurrentColor(partOfPattern);
    ctx.globalAlpha = alpha;
    ctx.beginPath();
    ctx.arc(centerX, centerY, size / 2.0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1.0;
  }
}

/** 宿主桥：ArkTS 禁止无类型对象字面量，故用具名类实现 LockPatternHost（等价于匿名回调容器） */
class LockPatternHostBridge implements LockPatternHost {
  private redrawFn: () => void;
  private hapticFn: () => void;
  private tickerFn: () => void;

  constructor(redrawFn: () => void, hapticFn: () => void, tickerFn: () => void) {
    this.redrawFn = redrawFn;
    this.hapticFn = hapticFn;
    this.tickerFn = tickerFn;
  }

  requestRedraw(): void {
    this.redrawFn();
  }

  requestHaptic(): void {
    this.hapticFn();
  }

  requestTicker(): void {
    this.tickerFn();
  }
}
/**
 * 图案锁控件本体。
 * 用法（ui-scene）：
 *   private lockCtrl: LockPatternController = new LockPatternController();
 *   ...
 *   LockPatternView({ controller: this.lockCtrl, isLightTheme: true })
 *     .width('100%').aspectRatio(1)
 */
@Component
export struct LockPatternView {
  controller: LockPatternController = new LockPatternController();
  @Prop @Watch('onThemeChanged') isLightTheme: boolean = true;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private timerId: number = -1;
  private viewW: number = 0;
  private viewH: number = 0;
  private hostBridge: LockPatternHostBridge = new LockPatternHostBridge(() => {}, () => {}, () => {});

  private onThemeChanged(): void {
    this.controller.isLightTheme = this.isLightTheme;
    this.redraw();
  }

  aboutToAppear(): void {
    // 装配期接线检查：把接线错误前移到装配期（可被日志巡检/单测覆盖）
    this.controller.checkWiring();
    this.controller.isLightTheme = this.isLightTheme;
    this.hostBridge = new LockPatternHostBridge(
      (): void => {
        this.redraw();
      },
      (): void => {
        // 震动由 entry 侧注入（controller.hapticExecutor / @ohos.vibrator），此处默认无操作
      },
      (): void => {
        this.startTicker();
      }
    );
    this.controller.attach(this.hostBridge);
  }

  aboutToDisappear(): void {
    this.stopTicker();
    this.controller.detach();
  }

  private redraw(): void {
    if (!this.ready || this.viewW <= 0 || this.viewH <= 0) {
      return;
    }
    this.controller.isLightTheme = this.isLightTheme;
    this.controller.draw(this.ctx);
  }

  private startTicker(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      const now: number = Date.now();
      const keepGoing: boolean = this.controller.tick(now);
      this.redraw();
      if (!keepGoing) {
        this.stopTicker();
      }
    }, 16);
  }

  private stopTicker(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.ready = true;
        this.redraw();
      })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.viewW = newValue.width as number;
        this.viewH = newValue.height as number;
        this.controller.onSizeChanged(this.viewW, this.viewH);
        this.redraw();
      })
      .onTouch((event: TouchEvent) => {
        if (!this.controller.inputEnabled || event.touches.length === 0) {
          return;
        }
        // 上游为主触点语义，多指时只处理第一个触点
        const p: TouchObject = event.touches[0];
        const x: number = p.x;
        const y: number = p.y;
        if (event.type === TouchType.Down) {
          this.controller.handleActionDown(x, y);
        } else if (event.type === TouchType.Move) {
          this.controller.handleActionMove(x, y);
        } else if (event.type === TouchType.Up) {
          this.controller.handleActionUp();
        } else if (event.type === TouchType.Cancel) {
          this.controller.handleActionCancel();
        }
      })
  }
}
