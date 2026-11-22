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
// OHOS 移植：见 input_stream.h 顶部说明。
//

#include "config.h"
#ifdef STREAM_SUPPORT_INPUT

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#include "../log.h"
#include "../utils.h"
#include "input_stream.h"

InputStream* create_input_stream_from_memory(const void* data, size_t size)
{
  InputStream* inputStream;

  if (data == NULL && size > 0) {
    LOGE(MSG("Can't create input stream from null buffer"));
    return NULL;
  }

  inputStream = (InputStream*) malloc(sizeof(InputStream));
  if (inputStream == NULL) {
    WTF_OM;
    return NULL;
  }

  inputStream->type = INPUT_STREAM_SOURCE_MEMORY;
  inputStream->data = (const unsigned char*) data;
  inputStream->size = size;
  inputStream->position = 0;
  inputStream->fd = -1;
  inputStream->fd_size = size;

  return inputStream;
}

InputStream* create_input_stream_from_fd(int fd)
{
  InputStream* inputStream;
  struct stat st;

  if (fd < 0) {
    LOGE(MSG("Invalid file descriptor %d"), fd);
    return NULL;
  }

  inputStream = (InputStream*) malloc(sizeof(InputStream));
  if (inputStream == NULL) {
    WTF_OM;
    return NULL;
  }

  inputStream->type = INPUT_STREAM_SOURCE_FD;
  inputStream->data = NULL;
  inputStream->size = 0;
  inputStream->position = 0;
  inputStream->fd = fd;
  inputStream->fd_size = 0;
  if (fstat(fd, &st) == 0 && st.st_size > 0) {
    inputStream->fd_size = (size_t) st.st_size;
  }

  return inputStream;
}

void destroy_input_stream(JNIEnv* env, InputStream** inputStream)
{
  (void) env;
  if (inputStream != NULL && *inputStream != NULL) {
    free(*inputStream);
    *inputStream = NULL;
  }
}

size_t read_input_stream(JNIEnv* env, InputStream* inputStream, unsigned char* buffer, int offset, size_t size)
{
  size_t readSize = 0;

  (void) env;

  if (inputStream == NULL || buffer == NULL || size == 0) {
    return 0;
  }

  if (inputStream->type == INPUT_STREAM_SOURCE_MEMORY) {
    size_t remain;
    size_t position = inputStream->position;

    if (position >= inputStream->size) {
      return 0;
    }
    remain = inputStream->size - position;
    readSize = MIN(remain, size);
    memcpy(buffer + offset, inputStream->data + position, readSize);
    inputStream->position = position + readSize;
    return readSize;
  }

  while (readSize < size) {
    ssize_t len = pread(inputStream->fd, buffer + offset + readSize, size - readSize,
        (off_t) (inputStream->position + readSize));
    if (len < 0) {
      LOGE(MSG("Can't read from fd %d"), inputStream->fd);
      break;
    }
    if (len == 0) {
      break; /* EOF */
    }
    readSize += (size_t) len;
  }
  inputStream->position += readSize;

  return readSize;
}

void close_input_stream(JNIEnv* env, InputStream* inputStream)
{
  (void) env;
  if (inputStream == NULL) {
    return;
  }
  /* 缓冲区源无需关闭；fd 由调用方（NAPI 层）负责关闭，避免重复 close */
  if (inputStream->type == INPUT_STREAM_SOURCE_MEMORY) {
    inputStream->position = inputStream->size;
  }
}

#endif // STREAM_SUPPORT_INPUT
