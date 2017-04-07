{-# LANGUAGE TypeOperators #-}
-- module Main
-- where

-- random numbers: https://github.com/tmcdonell/mwc-random-accelerate
--
-- linear vector things: https://github.com/tmcdonell/linear-accelerate

-- ask why these imports needed
import Prelude                                    as P

import Data.Array.Accelerate                      as A
import Data.Array.Accelerate.Interpreter          as I
-- import Data.Array.Accelerate.System.Random.MWC

-- import MMult                                      ( Matrix, mmult )


type Matrix a = Array DIM2 a

-- trying to translate coursera machine learning neural network 
-- into accelerate or haskell version...

-- Robs
sigmoid :: Exp Float -> Exp Float
sigmoid z = 1.0 / (1.0 + exp(-z))

-- http://stackoverflow.com/questions/9748474/reading-from-input-files-in-haskell
readWords :: [String] -> [Float]
readWords [] = []
readWords (x:xs) = [read x :: Float] P.++ readWords xs

--parseFile :: String -> Int -> Int -> IO (Array (Int, Int) Int)
--parseFile filename rows cols = do
--    matrix <- liftM readWords $ readFile filename
--    return $ listArray ((1,1), (rows, cols)) matrix

-- loadDataMatrix :: IO ([Float])
-- loadDataMatrix = do
--     content <- readFile "trainsample100.txt"
--     let strarr = words content
--     let dbarr = readWords strarr
--     return dbarr

loadSampleA :: IO (A.Array DIM2 Float)
loadSampleA = do
    content <- readFile "trainsample100.txt"
    let strarr = words content
    let dbarr = readWords strarr
    let arr = A.fromList (Z:.400:.100) dbarr :: A.Array DIM2 Float
    return arr

loadLabelA :: IO (Vector Float)
loadLabelA = do
    content <- readFile "trainlabel100.txt"
    let strarr = words content
    let dbarr = readWords strarr
    let arr = A.fromList (Z:.100) dbarr :: Vector Float
    return arr

generateTheta :: Int -> Vector Float
generateTheta n = A.fromList (Z :. n) (P.replicate n 0) :: Vector Float
--  withSystemRandom $ \gen ->
--    randomArray (uniformR (0,1)) (Z :. n)

{--
-- matlab function: lrCostFunction(theta, X, y, lambda) = [J, grad]
lrCostFunction :: A.Array DIM2 Float -> A.Array DIM2 Float -> A.Array DIM1 Float -> Exp Float -> (Exp Float, A.Array DIM2 Float)
rCostFunction theta x y lambda = (j, grad)
    where
--      j = (1/m) * sum(-y.*(log(sigmoid(x * theta)))         -- first bit
--                      - (1 - y).*log(1-sigmoid(x*theta)))   -- second bit
--        + (lambda/(2*m))*(sum(temp.^2))                     -- regularization
--
        j              = (1/m) * sum (firstbit - secondbit) + regularization
        firstbit       = A.zipWith (*) (use (-y)) (use (map (log . sigmoid) (x * theta)))
        secondbit      = A.zipWith (*) (1 - y) (use (map log (1 - sigmoid (x * theta))))
        regularization = lambda / (2*m) * (foldr 0 [x^2 | x <- temp])
        temp           = 0 -- TODO theta (weights)
        lambda         = 0 -- TODO
        m              = A.length (use y) -- y is a vector because it is the number of training examples
--}


lrCostFunction
    :: Acc (Vector Float)               -- theta
    -> Acc (Matrix Float)               -- x
    -> Acc (Vector Float)               -- y (training .. bit?)
    -> Exp Float                        -- ??
    -- -> Acc (Scalar Float, Matrix Float)
    -> (Acc (Scalar Float), Acc (Vector Float))
lrCostFunction theta xs ys lambda = (j, grad)  -- lift :: (Acc (Scalar Float), Acc (Vector Float)) -> Acc (Scalar Float, Matrix Float)
  where
    grad :: Acc (Vector Float)
    grad = use $ fromList (Z :. 0) []

    m :: Exp Int
    m = A.length ys

    Z :. h :. w = unlift (shape xs) :: Z :. Exp Int :. Exp Int

    lambda :: Exp Float       -- learning rate
    lambda = undefined

    -- 1.3.1
    j :: Acc (Scalar Float)   -- error?
    j = A.map (\x -> x / A.fromIntegral m)
      $ A.sum
      $ A.zipWith3 (\x y t -> -y * log (sigmoid (t * x)) - (1 - y) * log (1 - sigmoid (t * x))) xs yy tt

    -- replicate column vector y into a matrix; where the column is replicated
    -- 'w' times across to form the matrix:
    --
    --   y1        y1 y1 y1 ...
    --   y2   ->   y2 y2 y2 ...
    --   ...             ...
    --
    yy :: Acc (Matrix Float)
    yy  = A.replicate (lift (Z :. All :. w)) ys

    -- same but replicate so that every row is the same, and is 'h' rows high
    --
    --   t1 t2 t3  ->  t1 t2 t3 ...
    --                 t1 t2 t3 ...
    --                    ...
    --
    tt :: Acc (Matrix Float)
    tt = A.replicate (lift (Z :. h :. All)) theta


cubicExtrapolate :: Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> (Exp Float, Exp Float, Exp Float)
cubicExtrapolate d2 d3 f2 f3 z3 = (a, b, z2)
                         where
                             a = 6*(f2 - f3)/z3 + 3*(d2 + d3)
                             b = 3*(f3 - f2) - z3*(d3 + 2*d2)
                             z2 = (-d2*z3*z3)/(b + P.sqrt (b*b - a*d2*z3*z3))

cubicFit :: Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float
cubicFit d2 d3 f2 f3 z3 = z2
                         where
                             a = 6*(f2 - f3)/z3 + 3*(d2 + d3)
                             b = 3*(f3 - f2) - z3*(d3 + 2*d2)
                             z2 = (P.sqrt (b*b - a*d2*z3*z3) - b)/a

quadraticFit :: Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float
quadraticFit d3 f2 f3 z3 = z3 - (0.5*d3*z3*z3)/(d3*z3 + f2 - f3)

innerWhile :: Acc (Vector Float) -> Acc (Vector Float) -> Exp Float -> Exp Float -> Exp Float -> Exp Float
 -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Acc (Matrix Float) -> Acc (Vector Float) -> Exp Float 
 -> (Acc (Vector Float), Acc (Scalar Float), Acc (Scalar Float), Exp Float, Exp Float, Exp Float)
innerWhile theta s d1 d2 d3 f1 f2 f3 z1 z2''' z3 xs ys lambda = (theta', d2', f2', z1', z2, z3')
    where
        condition = (f2 > (f1 + z1 * 0.01 * d1)) || (d2 > -0.5 * d1)
    -- if condition == True, then loop, otherwise return/break innerWhile loop
        z2'' | (f2 > f1) = quadraticFit d3 f2 f3 z3
             | otherwise = cubicFit d2 d3 f2 f3 z3
        z2'  | (z2'' /= z2'') = z3/2
             | otherwise = z2''
        z2 = max (min z2' (0.1 * z3)) (0.9 * z3)
        z1' = z1 + z2
        theta' = A.zipWith (+) theta (multScalerVector z2 s)
        (f2', df2') = lrCostFunction theta' xs ys lambda
        d2' = A.sum (A.zipWith (*) df2' s)
        z3' = z3 - z2;
    -- return z2 -- TODO

outerWhile :: Acc (Vector Float) -> Acc (Vector Float) -> Exp Float -> Exp Float -> Exp Float -> Exp Float
 -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Acc (Matrix Float) -> Acc (Vector Float) -> Exp Float -> Exp Float 
 -> (Acc (Vector Float), Acc(Scalar Float), Exp Float, Acc(Scalar Float), Exp Float, Exp Float, Exp Float, Exp Float, Acc (Vector Float))
outerWhile theta s d1 d2 d3 f1 f2 f3 z1 z2 z3 xs ys lambda limit = (theta', d2', d3', f2', f3', z1', z2', z3', df2')
    where
        -- innerWhile here
        (a, b, z2') = cubicExtrapolate d2 d3 f2 f3 z3
        z2'' | ((z2 /= z2 || z2 < 0) && limit < -0.5) = z1 * 2.0
             | ((z2 /= z2 || z2 < 0) && limit >= -0.5) = (limit - z1)/2
             | (limit > -0.5 && z2 + z1 > limit) = (limit - z1)/2
             | (limit < -0.5 && z2 + z1 > z1 * 3.0) = z1 * 2.0
             | (z2 < -z3 * 0.1) = -z3 * 0.1
             | (limit > -0.5 && z2 < (limit -z1) * 0.9) = (limit -z1) * 0.9
             | otherwise = z2'
        f3' = f2
        d3' = d2
        z3' = -z2''
        z1' = z1 + z2''
        theta' = A.zipWith (+) theta (multScalerVector z2'' s)
        (f2', df2') = lrCostFunction theta' xs ys lambda
        d2' = A.sum (A.zipWith (*) df2' s)
    -- return z2'' -- TODO

handleSuccess :: Acc (Vector Float) -> Acc (Vector Float) -> Exp Float -> Exp Float -> Exp Float -> Exp Float
 -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Acc (Matrix Float) -> Acc (Vector Float) -> Acc (Vector Float) -> Exp Float -> Exp Float -> IO (Exp Float)
handleSuccess theta s d1 d2 d3 f1 f2 f3 z1 z2 z3 xs df1 df2 lambda limit = do
    let f1' = f2
    -- let fX = fX' ++ [f1]
    -- s = (df2'*df2-df1'*df2)/(df1'*df1)*s - df2;      % Polack-Ribiere direction
    -- let s' = A.zipWith (-) (firstbit / secondbit) df2
    --         where
    --             firstbit = A.zipWith (-) (A.sum (A.zipWith (*) df2 df2)) (A.sum (A.zipWith (*) df1 df2))
    --             secondbit = multScalerVector (the (A.sum (A.zipWith (*) df1 df1))) s
    let df1' = df2
    let df2' = df1
    let d2' = A.sum (A.zipWith (*) df1 s)
    -- let (s'', d2'') | (d2' > 0) = (-df1', A.sum (A.zipWith (*) s s)) -- TODO one of the s should be -s
    --                 | otherwise = (s', d2')
    -- let z1' = z1 * (min 100 (d1/(d2-realmin))) -- TODO find what realmin is
    let d1' = d2'
    return z2;

multScalerVector :: Exp Float -> Acc (Vector Float) -> Acc (Vector Float)
multScalerVector f v = A.zipWith (*) f' v
    where
        f' = A.replicate (lift (Any :. h)) (unit f)
        Z :. h = unlift (shape v) :: Z :. Exp Int

-- fmincg
--     :: Acc (Vector Float)               -- initial_theta
--     -> Acc (Matrix Float)               -- x
--     -> Acc (Vector Float)               -- y (training .. bit?)
--     -> Exp Float                        -- ??
--     -> Exp Float                        -- c?
--     -> Acc (Vector Float)               -- final_theta
-- fmincg theta0 xs ys lambda c = theta
--   where

