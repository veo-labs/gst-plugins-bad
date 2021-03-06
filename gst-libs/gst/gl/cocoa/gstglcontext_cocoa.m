/*
 * GStreamer
 * Copyright (C) 2012 Matthew Waters <ystreet00@gmail.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <Cocoa/Cocoa.h>

#include "gstglcontext_cocoa.h"
#include "gstgl_cocoa_private.h"

static gboolean gst_gl_context_cocoa_create_context (GstGLContext *context, GstGLAPI gl_api,
    GstGLContext * other_context, GError **error);
static void gst_gl_context_cocoa_destroy_context (GstGLContext *context);
static guintptr gst_gl_context_cocoa_get_gl_context (GstGLContext * window);
static gboolean gst_gl_context_cocoa_activate (GstGLContext * context, gboolean activate);
static GstGLAPI gst_gl_context_cocoa_get_gl_api (GstGLContext * context);
static GstGLPlatform gst_gl_context_cocoa_get_gl_platform (GstGLContext * context);

#define GST_GL_CONTEXT_COCOA_GET_PRIVATE(o)  \
  (G_TYPE_INSTANCE_GET_PRIVATE((o), GST_GL_TYPE_CONTEXT_COCOA, GstGLContextCocoaPrivate))

GST_DEBUG_CATEGORY_STATIC (gst_gl_context_cocoa_debug);
#define GST_CAT_DEFAULT gst_gl_context_cocoa_debug

G_DEFINE_TYPE_WITH_CODE (GstGLContextCocoa, gst_gl_context_cocoa,
    GST_GL_TYPE_CONTEXT, GST_DEBUG_CATEGORY_INIT (gst_gl_context_cocoa_debug, "glcontext_cocoa", 0, "Cocoa GL Context"); );

static void
gst_gl_context_cocoa_class_init (GstGLContextCocoaClass * klass)
{
  GstGLContextClass *context_class = (GstGLContextClass *) klass;

  g_type_class_add_private (klass, sizeof (GstGLContextCocoaPrivate));

  context_class->destroy_context =
      GST_DEBUG_FUNCPTR (gst_gl_context_cocoa_destroy_context);
  context_class->create_context =
      GST_DEBUG_FUNCPTR (gst_gl_context_cocoa_create_context);
  context_class->get_gl_context =
      GST_DEBUG_FUNCPTR (gst_gl_context_cocoa_get_gl_context);
  context_class->activate = GST_DEBUG_FUNCPTR (gst_gl_context_cocoa_activate);
  context_class->get_gl_api =
      GST_DEBUG_FUNCPTR (gst_gl_context_cocoa_get_gl_api);
  context_class->get_gl_platform =
      GST_DEBUG_FUNCPTR (gst_gl_context_cocoa_get_gl_platform);
}

static void
gst_gl_context_cocoa_init (GstGLContextCocoa * context)
{
  context->priv = GST_GL_CONTEXT_COCOA_GET_PRIVATE (context);
}

/* Must be called in the gl thread */
GstGLContextCocoa *
gst_gl_context_cocoa_new (void)
{
  GstGLContextCocoa *context = g_object_new (GST_GL_TYPE_CONTEXT_COCOA, NULL);

  return context;
}

struct pixel_attr
{
  CGLPixelFormatAttribute attr;
  const gchar *attr_name;
};

static struct pixel_attr pixel_attrs[] = {
  {kCGLPFAAllRenderers, "All Renderers"},
  {kCGLPFADoubleBuffer, "Double Buffered"},
  {kCGLPFAStereo, "Stereo"},
  {kCGLPFAAuxBuffers, "Aux Buffers"},
  {kCGLPFAColorSize, "Color Size"},
  {kCGLPFAAlphaSize, "Alpha Size"},
  {kCGLPFADepthSize, "Depth Size"},
  {kCGLPFAStencilSize, "Stencil Size"},
  {kCGLPFAAccumSize, "Accum Size"},
  {kCGLPFAMinimumPolicy, "Minimum Policy"},
  {kCGLPFAMaximumPolicy, "Maximum Policy"},
  {kCGLPFASampleBuffers, "Sample Buffers"},
  {kCGLPFASamples, "Samples"},
  {kCGLPFAAuxDepthStencil, "Aux Depth Stencil"},
  {kCGLPFAColorFloat, "Color Float"},
  {kCGLPFAMultisample, "Multisample"},
  {kCGLPFASupersample, "Supersample"},
  {kCGLPFARendererID, "Renderer ID"},
  {kCGLPFANoRecovery, "No Recovery"},
  {kCGLPFAAccelerated, "Accelerated"},
  {kCGLPFAClosestPolicy, "Closest Policy"},
  {kCGLPFABackingStore, "Backing Store"},
  {kCGLPFADisplayMask, "Display Mask"},
  {kCGLPFAAllowOfflineRenderers, "Allow Offline Renderers"},
  {kCGLPFAAcceleratedCompute, "Accelerated Compute"},
  {kCGLPFAOpenGLProfile, "OpenGL Profile"},
  {kCGLPFAVirtualScreenCount, "Virtual Screen Count"},
#if MAC_OS_X_VERSION_MAX_ALLOWED < 1090
  {kCGLPFACompliant, "Compliant"},
  {kCGLPFARemotePBuffer, "Remote PBuffer"},
  {kCGLPFASingleRenderer, "Single Renderer"},
  {kCGLPFAWindow, "Window"},
#endif
#if MAC_OS_X_VERSION_MAX_ALLOWED < 1070
//  {kCGLPFAOffScreen, "Off Screen"},
//  {kCGLPFAPBuffer, "PBuffer"},
#endif
#if MAC_OS_X_VERSION_MAX_ALLOWED < 1060
//  {kCGLPFAFullScreen, "Full Screen"},
#endif
#if MAC_OS_X_VERSION_MAX_ALLOWED < 1050
//  {kCGLPFAMPSafe, "MP Safe"},
//  {kCGLPFAMultiScreen, "Multi Screen"},
//  {kCGLPFARobust, "Robust"},
#endif
};

void
gst_gl_context_cocoa_dump_pixel_format (CGLPixelFormatObj fmt)
{
  int i;

  for (i = 0; i < G_N_ELEMENTS (pixel_attrs); i++) {
    gint val;
    CGLError ret = CGLDescribePixelFormat (fmt, 0, pixel_attrs[i].attr, &val);

    if (ret != kCGLNoError) {
      GST_WARNING ("failed to get pixel format %p attribute %s", fmt, pixel_attrs[i].attr_name);
    } else {
      GST_DEBUG ("Pixel format %p attr %s = %i", fmt, pixel_attrs[i].attr_name,
          val);
    }
  }
}

CGLPixelFormatObj
gst_gl_context_cocoa_get_pixel_format (GstGLContextCocoa *context)
{
  return context->priv->pixel_format;
}

static gboolean
gst_gl_context_cocoa_create_context (GstGLContext *context, GstGLAPI gl_api,
    GstGLContext *other_context, GError **error)
{
  GstGLContextCocoa *context_cocoa = GST_GL_CONTEXT_COCOA (context);
  GstGLContextCocoaPrivate *priv = context_cocoa->priv;
  GstGLWindow *window = gst_gl_context_get_window (context);
  GstGLWindowCocoa *window_cocoa = GST_GL_WINDOW_COCOA (window);
  const GLint swapInterval = 1;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  CGLPixelFormatObj fmt = NULL;
  CGLContextObj glContext;
  CGLPixelFormatAttribute attribs[] = {
    kCGLPFADoubleBuffer,
    kCGLPFAAccumSize, 32,
    0
  };
  CGLError ret;
  gint npix;

  priv->gl_context = nil;
  if (other_context)
    priv->external_gl_context = (CGLContextObj) gst_gl_context_get_gl_context (other_context);
  else
    priv->external_gl_context = NULL;

  if (priv->external_gl_context) {
    fmt = CGLGetPixelFormat (priv->external_gl_context);
  }

  if (!fmt) {
    ret = CGLChoosePixelFormat (attribs, &fmt, &npix);
    if (ret != kCGLNoError) {
      g_set_error (error, GST_GL_CONTEXT_ERROR,
          GST_GL_CONTEXT_ERROR_WRONG_CONFIG, "cannot choose a pixel format: %s", CGLErrorString (ret));
      goto error;
    }
  }

  gst_gl_context_cocoa_dump_pixel_format (fmt);

  ret = CGLCreateContext (fmt, priv->external_gl_context, &glContext);
  if (ret != kCGLNoError) {
    g_set_error (error, GST_GL_CONTEXT_ERROR, GST_GL_CONTEXT_ERROR_CREATE_CONTEXT,
        "failed to create context: %s", CGLErrorString (ret));
    goto error;
  }

  context_cocoa->priv->pixel_format = fmt;
  context_cocoa->priv->gl_context = glContext;

  _invoke_on_main ((GstGLWindowCB) gst_gl_window_cocoa_create_window,
      window_cocoa);

  if (!context_cocoa->priv->gl_context) {
    goto error;
  }

  GST_INFO_OBJECT (context, "GL context created: %p", context_cocoa->priv->gl_context);

  CGLSetCurrentContext (context_cocoa->priv->gl_context);

  /* Back and front buffers are swapped only during the vertical retrace of the monitor.
   * Discarded if you configured your driver to Never-use-V-Sync.
   */
  CGLSetParameter (context_cocoa->priv->gl_context, kCGLCPSwapInterval, &swapInterval);

  gst_object_unref (window);
  [pool release];

  return TRUE;

error:
  gst_object_unref (window);
  [pool release];
  return FALSE;
}

static void
gst_gl_context_cocoa_destroy_context (GstGLContext *context)
{
  /* FIXME: Need to release context and other things? */
}

static guintptr
gst_gl_context_cocoa_get_gl_context (GstGLContext * context)
{
  return (guintptr) GST_GL_CONTEXT_COCOA (context)->priv->gl_context;
}

static gboolean
gst_gl_context_cocoa_activate (GstGLContext * context, gboolean activate)
{
  GstGLContextCocoa *context_cocoa = GST_GL_CONTEXT_COCOA (context);
  gpointer context_handle = activate ? context_cocoa->priv->gl_context : NULL;

  return kCGLNoError == CGLSetCurrentContext (context_handle);
}

static GstGLAPI
gst_gl_context_cocoa_get_gl_api (GstGLContext * context)
{
  return GST_GL_API_OPENGL;
}

static GstGLPlatform
gst_gl_context_cocoa_get_gl_platform (GstGLContext * context)
{
  return GST_GL_PLATFORM_CGL;
}

guintptr
gst_gl_context_cocoa_get_current_context (void)
{
  return (guintptr) CGLGetCurrentContext ();
}
