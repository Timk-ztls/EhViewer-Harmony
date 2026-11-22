/*
 * U-02b：`GalleryDetailScene` 的薄子类。默认注入 `UnavailableDetailClient`（warn 兜底）。
 */
import { GalleryDetailScene } from './GalleryDetailScene';
import { UnavailableDetailClient } from './GalleryDetailScene';

export class GalleryDetailSceneConcrete extends GalleryDetailScene {
  constructor() {
    super();
    this.setDetailClient(new UnavailableDetailClient());
  }

  getSceneName(): string {
    return 'GalleryDetailScene';
  }
}
