use crate::codec::EncoderApi;
use crate::{codec::EncoderCfg, EncodeFrame, EncodeInput, EncodeYuvFormat, Error, Pixfmt};
use hbb_common::{
    anyhow::{anyhow, bail},
    message_proto::Chroma,
    ResultType,
};

#[derive(Clone, Copy, Debug)]
pub struct AomEncoderConfig {
    pub width: u32,
    pub height: u32,
    pub quality: f32,
    pub keyframe_interval: Option<usize>,
}

pub struct AomEncoder {
    yuvfmt: EncodeYuvFormat,
}

impl EncoderApi for AomEncoder {
    fn new(cfg: EncoderCfg, i444: bool) -> ResultType<Self>
    where
        Self: Sized,
    {
        match cfg {
            EncoderCfg::AOM(config) => Ok(Self {
                yuvfmt: make_yuvfmt(config.width as usize, config.height as usize, i444),
            }),
            _ => Err(anyhow!("encoder type mismatch")),
        }
    }

    fn encode_to_message(&mut self, _frame: EncodeInput, _ms: i64) -> ResultType<hbb_common::message_proto::VideoFrame> {
        bail!("AV1/AOM disabled in Windows build")
    }

    fn yuvfmt(&self) -> EncodeYuvFormat {
        self.yuvfmt.clone()
    }

    fn set_quality(&mut self, _ratio: f32) -> ResultType<()> {
        Ok(())
    }

    fn bitrate(&self) -> u32 {
        0
    }

    fn support_changing_quality(&self) -> bool {
        false
    }

    fn latency_free(&self) -> bool {
        true
    }

    fn is_hardware(&self) -> bool {
        false
    }

    fn disable(&self) {}
}

impl AomEncoder {
    pub fn encode<'a>(&'a mut self, _ms: i64, _data: &[u8], _stride_align: usize) -> crate::Result<EncodeFrames<'a>> {
        Err(Error::FailedCall("AV1/AOM disabled in Windows build".to_string()))
    }
}

pub struct EncodeFrames<'a> {
    _marker: std::marker::PhantomData<&'a ()>,
}

impl<'a> Iterator for EncodeFrames<'a> {
    type Item = EncodeFrame<'a>;

    fn next(&mut self) -> Option<Self::Item> {
        None
    }
}

pub struct AomDecoder;

impl AomDecoder {
    pub fn new() -> crate::Result<Self> {
        Ok(Self)
    }

    pub fn decode<'a>(&'a mut self, _data: &[u8]) -> crate::Result<DecodeFrames<'a>> {
        Ok(DecodeFrames {
            _marker: std::marker::PhantomData,
        })
    }

    pub fn flush<'a>(&'a mut self) -> crate::Result<DecodeFrames<'a>> {
        Ok(DecodeFrames {
            _marker: std::marker::PhantomData,
        })
    }
}

pub struct DecodeFrames<'a> {
    _marker: std::marker::PhantomData<&'a ()>,
}

impl<'a> Iterator for DecodeFrames<'a> {
    type Item = Image;

    fn next(&mut self) -> Option<Self::Item> {
        None
    }
}

pub struct Image;

impl Image {
    pub fn new() -> Self {
        Self
    }

    pub fn is_null(&self) -> bool {
        true
    }
}

impl crate::common::GoogleImage for Image {
    fn width(&self) -> usize {
        0
    }

    fn height(&self) -> usize {
        0
    }

    fn stride(&self) -> Vec<i32> {
        vec![0, 0, 0]
    }

    fn planes(&self) -> Vec<*mut u8> {
        vec![std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut()]
    }

    fn chroma(&self) -> Chroma {
        Chroma::I420
    }
}

fn make_yuvfmt(width: usize, height: usize, i444: bool) -> EncodeYuvFormat {
    if i444 {
        let stride = width;
        let y_len = stride * height;
        let u_len = stride * height;
        EncodeYuvFormat {
            pixfmt: Pixfmt::I444,
            w: width,
            h: height,
            stride: vec![stride, stride, stride],
            u: y_len,
            v: y_len + u_len,
        }
    } else {
        let stride_y = width;
        let stride_uv = width.div_ceil(2);
        let chroma_h = height.div_ceil(2);
        let y_len = stride_y * height;
        let u_len = stride_uv * chroma_h;
        EncodeYuvFormat {
            pixfmt: Pixfmt::I420,
            w: width,
            h: height,
            stride: vec![stride_y, stride_uv, stride_uv],
            u: y_len,
            v: y_len + u_len,
        }
    }
}
