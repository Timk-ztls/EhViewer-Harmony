/*
 * Copyright 2015 Hippo Seven
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

//
// Created by Hippo on 10/19/2015.
//
// OHOS 移植：上游 InputStream 持有 java.io.InputStream 的 jobject 与反射得到的
// read/close 方法 id。鸿蒙侧没有 JVM，输入源改为「原生内存缓冲区」或「文件描述符」，
// read_input_stream 的签名保持不变，因此 patch_head_input_stream.c 与
// jni/image/*.c 无需改动。
//

#ifndef STREAM_INPUT_STREAM_H
#define STREAM_INPUT_STREAM_H

#include "config.h"
#ifdef STREAM_SUPPORT_INPUT

#include <jni.h>
#include <stddef.h>
#include <stdbool.h>

typedef enum {
  INPUT_STREAM_SOURCE_MEMORY = 0,
  INPUT_STREAM_SOURCE_FD = 1
} InputStreamSourceType;

typedef struct
{
  InputStreamSourceType type;
  const unsigned char* data;   /* MEMORY: 只读缓冲区，生命周期由调用方保证 */
  size_t size;                 /* MEMORY: 缓冲区长度 */
  size_t position;             /* 当前读取偏移（MEMORY/FD 共用） */
  int fd;                      /* FD: 文件描述符，读取用 pread，不改动 fd 偏移 */
  size_t fd_size;              /* FD: 文件总长（仅用于诊断） */
} InputStream;

InputStream* create_input_stream_from_memory(const void* data, size_t size);
InputStream* create_input_stream_from_fd(int fd);
void destroy_input_stream(JNIEnv* env, InputStream** inputStream);
size_t read_input_stream(JNIEnv* env, InputStream* inputStream, unsigned char* buffer, int offset, size_t size);
void close_input_stream(JNIEnv* env, InputStream* inputStream);

#endif // STREAM_SUPPORT_INPUT

#endif // STREAM_INPUT_STREAM_H
