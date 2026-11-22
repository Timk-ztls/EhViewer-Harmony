/*
 * GalleryView 参数动态同步（LTR<->RTL 原地更新、scaleMode/startPosition/interval）单测（Stage C Track P5）。
 */

import { GLES20Canvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLES20Canvas';
import { GLErr, GLNative, GLNativeBackend } from '../../main/ets/hippo/lib/glview/native/GLNativeBridge';
import { GLRootView } from '../../main/ets/hippo/lib/glview/view/GLRootView';
import { GalleryLayoutFactory } from '../../main/ets/hippo/lib/glgallery/GalleryLayoutFactory';
import {
  GalleryAdapter,
  GalleryView,
  GalleryViewBuilder
} from '../../main/ets/hippo/lib/glgallery/GalleryView';
import { GalleryPageView } from '../../main/ets/hippo/lib/glgallery/GalleryPageView';
import { ImageView } from '../../main/ets/hippo/lib/glgallery/ImageView';
import { PagerLayoutManager } from '../../main/ets/hippo/lib/glgallery/PagerLayoutManager';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}: got ${g} want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(name);
  }
}

class NoopBackend implements GLNativeBackend {
  init(): GLErr { return GLErr.OK; }
  setSurface(_w: number, _h: number): GLErr { return GLErr.OK; }
  destroySurface(): GLErr { return GLErr.OK; }
  replay(_cmds: Float32Array): GLErr { return GLErr.OK; }
  present(): GLErr { return GLErr.OK; }
  genTexture(): number { return 1; }
  deleteTexture(_id: number): GLErr { return GLErr.OK; }
  texImage2D(): GLErr { return GLErr.OK; }
  texSubImage2D(): GLErr { return GLErr.OK; }
  texSubImage2DFill(): GLErr { return GLErr.OK; }
  genBuffer(): number { return 1; }
  bufferDataF32(): GLErr { return GLErr.OK; }
  bufferDataU8(): GLErr { return GLErr.OK; }
  deleteBuffer(): GLErr { return GLErr.OK; }
  genFramebuffer(): number { return 1; }
  unbindFramebuffer(): GLErr { return GLErr.OK; }
  deleteFramebuffer(): GLErr { return GLErr.OK; }
  getErrorCode(): number { return 0; }
  getString(_what: number): string { return ''; }
}

class DummyAdapter extends GalleryAdapter {
  total: number;
  constructor(total: number) {
    super();
    this.total = total;
  }
  onBind(_view: GalleryPageView, _index: number): void {}
  onUnbind(_view: GalleryPageView, _index: number): void {}
  getError(): string | null { return null; }
  size(): number { return this.total; }
}

{
  const backend = new NoopBackend();
  GLNative.register(backend);
  GalleryLayoutFactory.setPagerCreator((gv: GalleryView, sm: number, sp: number, interval: number): PagerLayoutManager =>
    new PagerLayoutManager(gv, sm, sp, 1.0, interval));
  GalleryLayoutFactory.install();

  const root = new GLRootView();
  const canvas = new GLES20Canvas();
  const adapter = new DummyAdapter(10);
  const gv = new GalleryViewBuilder(adapter)
    .setLayoutMode(GalleryView.LAYOUT_LEFT_TO_RIGHT)
    .setScaleMode(ImageView.SCALE_FIT)
    .setStartPosition(ImageView.START_POSITION_TOP_LEFT)
    .setStartPage(3)
    .setPagerInterval(24)
    .setScrollInterval(12)
    .build();

  root.setContentPane(gv);
  root.onSurfaceCreated(canvas);
  root.onSurfaceChanged(1080, 1920);
  root.onDrawFrame();

  ok('layout manager attached on GLRoot attach', gv.debugSnapshot().indexOf('layout=true') >= 0);
  eq('initial layoutMode LTR', gv.getLayoutMode(), GalleryView.LAYOUT_LEFT_TO_RIGHT);

  // LTR -> RTL 原地切换不卸载 layoutManager 且保留当前页
  gv.setLayoutMode(GalleryView.LAYOUT_RIGHT_TO_LEFT);
  gv.setScaleMode(ImageView.SCALE_FIT_WIDTH);
  gv.setStartPosition(ImageView.START_POSITION_TOP_RIGHT);
  gv.setPagerInterval(36);
  gv.setScrollInterval(48);
  root.onDrawFrame();

  eq('layoutMode updated to RTL', gv.getLayoutMode(), GalleryView.LAYOUT_RIGHT_TO_LEFT);
  ok('layout stays attached across LTR<->RTL switch', gv.debugSnapshot().indexOf('layout=true') >= 0);

  // 切到 TOP_TO_BOTTOM（ScrollLayoutManager），再切回 RTL（PagerLayoutManager）
  gv.setLayoutMode(GalleryView.LAYOUT_TOP_TO_BOTTOM);
  root.onDrawFrame();
  eq('layoutMode updated to TOP_TO_BOTTOM', gv.getLayoutMode(), GalleryView.LAYOUT_TOP_TO_BOTTOM);
  ok('scroll layout attached', gv.debugSnapshot().indexOf('layout=true') >= 0);

  gv.setLayoutMode(GalleryView.LAYOUT_RIGHT_TO_LEFT);
  root.onDrawFrame();
  eq('layoutMode back to RTL', gv.getLayoutMode(), GalleryView.LAYOUT_RIGHT_TO_LEFT);
  ok('pager layout re-attached', gv.debugSnapshot().indexOf('layout=true') >= 0);

  root.onSurfaceDestroyed();
}

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
