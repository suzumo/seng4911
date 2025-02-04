
module Data.Load.MINST (

  loadImages,
  loadLabels,

) where

import Control.Monad
import Data.Binary.Get
import Data.ByteString
import Data.Word
import qualified Data.ByteString                as B
import qualified Data.ByteString.Lazy           as L

import Data.Array.Accelerate.IO
import Data.Array.Accelerate                    ( Array, DIM1, DIM3, Z(..), (:.)(..) )


-- | Read a MINST image file
--
loadImages :: FilePath -> IO (Array DIM3 Word8)
loadImages f = do
  content <- L.readFile f
  let (imageCount, height, width, pixels) = runGet deserialiseImages content
  fromByteString (Z:.imageCount:.height:.width) pixels

-- | Read a MINST label file
--
loadLabels :: FilePath -> IO (Array DIM1 Word8)
loadLabels f = do
  content <- L.readFile f
  let labels = runGet deserialiseLabels content
  fromByteString (Z :. B.length labels) labels


-- MNIST Image file format
--
-- [offset] [type]          [value]          [description]
-- 0000     32 bit integer  0x00000803(2051) magic number
-- 0004     32 bit integer  ??               number of images
-- 0008     32 bit integer  28               number of rows
-- 0012     32 bit integer  28               number of columns
-- 0016     unsigned byte   ??               pixel
-- 0017     unsigned byte   ??               pixel
-- ........
-- xxxx     unsigned byte   ??               pixel
--
-- Pixels are organized row-wise. Pixel values are 0 to 255. 0 means background (white), 255
-- means foreground (black).
--
deserialiseImages :: Get (Int, Int, Int, ByteString)
deserialiseImages = do
  magicNumber <- getWord32be
  when (magicNumber /= 2051) $ fail "Not a valid MNIST image file"
  imageCount <- fromIntegral <$> getWord32be
  height     <- fromIntegral <$> getWord32be
  width      <- fromIntegral <$> getWord32be
  pixels     <- getByteString (imageCount * height * width)
  return (imageCount, height, width, pixels)

-- MNIST Label file format
--
-- [offset] [type]          [value]          [description]
-- 0000     32 bit integer  0x00000801(2049) magic number (MSB first)
-- 0004     32 bit integer  60000            number of items
-- 0008     unsigned byte   ??               label
-- 0009     unsigned byte   ??               label
-- ........
-- xxxx     unsigned byte   ??               label
-- The labels values are 0 to 9.
--
deserialiseLabels :: Get ByteString
deserialiseLabels = do
  magicNumber <- getWord32be
  when (magicNumber /= 2049) $ fail "Not a valid MNIST label file"
  imageCount <- fromIntegral <$> getWord32be
  labels     <- getByteString imageCount
  return $! labels

