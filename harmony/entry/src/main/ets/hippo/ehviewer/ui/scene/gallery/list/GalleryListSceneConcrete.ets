/*
 * U-02b：`GalleryListScene` 的薄子类（父类是 abstract，需具体子类才能进 SceneRegistry）。
 *
 * 约束（Lead 裁定）：薄子类每行必须属于三类之一 ——
 *   ① extends 父类  ② 构造里注入默认实现（父类 setter）  ③ 覆盖 getSceneName() 之类纯标识方法
 * 出现 if/循环/请求 → 说明它不该是薄子类。
 *
 * 注入的默认实现都是本仓库已有的 `Unavailable*` 兜底类（warn 日志 + 安全返回值），
 * 生产接线时由宿主用真实实现覆盖同名 setter。
 */
import { GalleryListScene } from './GalleryListScene';
import {
  UnavailableFavoritesRepository, UnavailableDownloadEnqueuer
} from './GalleryListScene';

export class GalleryListSceneConcrete extends GalleryListScene {
  constructor() {
    super();
    this.setFavoritesRepository(new UnavailableFavoritesRepository());
    this.setDownloadEnqueuer(new UnavailableDownloadEnqueuer());
  }

  getSceneName(): string {
    return 'GalleryListScene';
  }
}
