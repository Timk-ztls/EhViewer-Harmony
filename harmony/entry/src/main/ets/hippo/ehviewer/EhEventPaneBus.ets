/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { EhApplication } from './EhApplication';

export class EhEventPaneMessage {
  readonly html: string;
  readonly body: string;

  constructor(html: string, body: string) {
    this.html = html;
    this.body = body;
  }
}

export type EhEventPaneListener = (msg: EhEventPaneMessage) => void;

/**
 * In-memory event pane delivery bus wiring `EhEngine._eventPaneHook` -> UI host Material dialog.
 * Respects `EhApplication.shouldShowEventPane(html)` (which checks `Settings.getShowEhEvents()`).
 */
export class EhEventPaneBus {
  private static readonly MAX_PENDING: number = 3;
  private static sInstance: EhEventPaneBus | null = null;

  private listener: EhEventPaneListener | null = null;
  private pendingQueue: EhEventPaneMessage[] = [];
  private lastShownBody: string = '';

  static getInstance(): EhEventPaneBus {
    if (EhEventPaneBus.sInstance === null) {
      EhEventPaneBus.sInstance = new EhEventPaneBus();
    }
    return EhEventPaneBus.sInstance;
  }

  static resetForTest(): void {
    const bus: EhEventPaneBus = EhEventPaneBus.getInstance();
    bus.listener = null;
    bus.pendingQueue = [];
    bus.lastShownBody = '';
  }

  static formatEventHtml(html: string): string {
    if (html.length === 0) {
      return '';
    }
    let text: string = html
      .replace(/<\s*br\s*\/?>/gi, '\n')
      .replace(/<\/\s*(?:p|div|li|tr|h[1-6])\s*>/gi, '\n\n')
      .replace(/<[^>]*>/g, '');

    text = EhEventPaneBus.decodeEntities(text);
    const lines: string[] = text.split('\n');
    const cleanedLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].replace(/\s+/g, ' ').trim();
      cleanedLines.push(line);
    }
    return cleanedLines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }

  private static decodeEntities(input: string): string {
    return input
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;|&apos;/gi, "'")
      .replace(/&#(\d+);/g, (_m: string, codeStr: string): string => {
        const code: number = Number.parseInt(codeStr, 10);
        return Number.isFinite(code) && code > 0 ? String.fromCharCode(code) : '';
      })
      .replace(/&#x([0-9a-fA-F]+);/g, (_m: string, hexStr: string): string => {
        const code: number = Number.parseInt(hexStr, 16);
        return Number.isFinite(code) && code > 0 ? String.fromCharCode(code) : '';
      });
  }

  publishHtml(html: string | null): boolean {
    if (!EhApplication.shouldShowEventPane(html)) {
      return false;
    }
    const rawHtml: string = html as string;
    const body: string = EhEventPaneBus.formatEventHtml(rawHtml);
    if (body.length === 0) {
      return false;
    }
    if (body === this.lastShownBody) {
      return false;
    }
    for (let i = 0; i < this.pendingQueue.length; i++) {
      if (this.pendingQueue[i].body === body) {
        return false;
      }
    }
    this.lastShownBody = body;
    const msg: EhEventPaneMessage = new EhEventPaneMessage(rawHtml, body);
    if (this.listener !== null) {
      this.listener(msg);
      return true;
    }
    if (this.pendingQueue.length >= EhEventPaneBus.MAX_PENDING) {
      this.pendingQueue.shift();
    }
    this.pendingQueue.push(msg);
    return true;
  }

  subscribe(listener: EhEventPaneListener | null): void {
    this.listener = listener;
  }

  unsubscribe(listener: EhEventPaneListener): void {
    if (this.listener === listener) {
      this.listener = null;
    }
  }

  consumePending(): EhEventPaneMessage | null {
    if (this.pendingQueue.length === 0) {
      return null;
    }
    const next: EhEventPaneMessage | undefined = this.pendingQueue.shift();
    return next !== undefined ? next : null;
  }
}
