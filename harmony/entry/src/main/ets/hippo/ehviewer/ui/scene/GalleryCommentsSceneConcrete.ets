/*
 * U-02b：`GalleryCommentsScene` 的薄子类。默认注入 `UnavailableCommentClient`。
 */
import { GalleryCommentsScene } from './GalleryCommentsScene';
import { UnavailableCommentClient } from './GalleryCommentsScene';

export class GalleryCommentsSceneConcrete extends GalleryCommentsScene {
  constructor() {
    super();
    this.setCommentClient(new UnavailableCommentClient());
  }

  getSceneName(): string {
    return 'GalleryCommentsScene';
  }
}
