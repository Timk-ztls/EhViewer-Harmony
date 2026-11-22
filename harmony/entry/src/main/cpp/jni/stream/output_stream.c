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
// OHOS 移植：见 output_stream.h 顶部说明。
//

#include "config.h"
#ifdef STREAM_SUPPORT_OUTPUT

#include <stdlib.h>
#include <string.h>

#include "../log.h"
#include "../utils.h"
#include "output_stream.h"

#define OUTPUT_STREAM_INITIAL_CAPACITY (256 * 1024)

OutputStream* create_output_stream(void)
{
  OutputStream* outputStream = (OutputStream*) malloc(sizeof(OutputStream));
  if (outputStream == NULL) {
    WTF_OM;
    return NULL;
  }

  outputStream->capacity = OUTPUT_STREAM_INITIAL_CAPACITY;
  outputStream->size = 0;
  outputStream->data = (unsigned char*) malloc(outputStream->capacity);
  if (outputStream->data == NULL) {
    WTF_OM;
    free(outputStream);
    return NULL;
  }

  return outputStream;
}

const unsigned char* get_output_stream_data(OutputStream* outputStream)
{
  return outputStream == NULL ? NULL : outputStream->data;
}

size_t get_output_stream_size(OutputStream* outputStream)
{
  return outputStream == NULL ? 0 : outputStream->size;
}

void destroy_output_stream(JNIEnv* env, OutputStream** outputStream)
{
  (void) env;
  if (outputStream != NULL && *outputStream != NULL) {
    free((*outputStream)->data);
    (*outputStream)->data = NULL;
    free(*outputStream);
    *outputStream = NULL;
  }
}

size_t write_output_stream(JNIEnv* env, OutputStream* outputStream, const unsigned char* buffer, int offset, size_t size)
{
  (void) env;

  if (outputStream == NULL || buffer == NULL || size == 0) {
    return 0;
  }

  if (outputStream->size + size > outputStream->capacity) {
    size_t capacity = outputStream->capacity;
    unsigned char* data;

    while (capacity < outputStream->size + size) {
      capacity *= 2;
    }
    data = (unsigned char*) realloc(outputStream->data, capacity);
    if (data == NULL) {
      WTF_OM;
      return 0;
    }
    outputStream->data = data;
    outputStream->capacity = capacity;
  }

  memcpy(outputStream->data + outputStream->size, buffer + offset, size);
  outputStream->size += size;

  return size;
}

void close_output_stream(JNIEnv* env, OutputStream* outputStream)
{
  (void) env;
  (void) outputStream;
  /* 内存缓冲区无需关闭，保留接口以对齐上游调用点 */
}

#endif // STREAM_SUPPORT_OUTPUT
