{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE RebindableSyntax #-}

-- random numbers: https://github.com/tmcdonell/mwc-random-accelerate
--
-- linear vector things: https://github.com/tmcdonell/linear-accelerate

-- ask why these imports needed
import Prelude                                    as P

import Data.Array.Accelerate                      as A
import Data.Array.Accelerate.Interpreter          as I
-- import Data.Array.Accelerate.System.Random.MWC
import Data.Array.Accelerate.Control.Lens

import MMult                                      ( mmult )

type Matrix a = Array DIM2 a


-- fmincgIO
--     :: Acc (Vector Float)               -- theta (weight vector)
--     -> Acc (Matrix Float)               -- X (data matrix)
--     -> Acc (Vector Float)               -- y (labels)
--     -> Exp Float                        -- lambda (learning rate)
--     -> Int                              -- number of repetitions?
--     -> IO (Acc (Scalar Float), Acc (Vector Float)) -- final j, final_theta
-- fmincgIO theta0 xs yc lambda i = do
--     let (f1, df1) = lrCostFunction theta0 xs yc lambda
--     let s = A.map negate df1
--     let d1 = A.map negate (the $ A.sum (A.zipWith (*) df1 df1))
--     let z1 = 1/(1-d1) -- red = 1
--     let theta1 = A.zipWith (+) theta0 (multScalerVector z1 s) -- X = X + z1*s
--     let (f2, df2) = lrCostFunction theta1 xs yc lambda -- [f2 df2] = eval(argstr)
--     let d2 = the (A.sum $ A.zipWith (A.*) df2 s)-- d2 = df2' * s
--     -- f3 = f1; d3 = d1; z3 = -z1;
--     let (theta3, d2'', d3, f2'', f3, z1'', z2', z3', df2') = outerWhile theta1 s d1 d2 d1 (the f1) (the f2) (the f1) z1 (-z1) xs yc lambda z1 -- limit = z1
--     let (s_, d1_, d2_, f1_, z1_, df1_, df2_) = handleSuccess theta3 s d1 (the d2'') d3 (the f1) (the f2'') f3 z1'' z2' z3' xs df1 df2' lambda z1 -- limit = z1
--     -- recursion??
--     if i P.== 0
--         then return (unit f1_, df2_)
--         else (fmincgIO df2_ xs yc lambda (i-1))


-- initial_theta = zeros(n + 1, 1);
-- options = optimset('GradObj', 'on', 'MaxIter', 50);
-- for c=1:num_labels,
--     [theta] = fmincg(@(t)(lrCostFunction(t, X, (y == c), lambda)), initial_theta, options);
--     all_theta(c,:) = theta;
-- end
-- i.e. fmincgIO receives lrCostFunction, theta, as arguments


-- fmincg(f, X, options, P1, P2, P3, P4, P5) = [X, fX, i]
-- Minimize a continuous differentialble multivariate function
-- f lrCostFunction, X theta, options null (in all essence), fX (?? - don't need?)
fmincg :: 
       Acc (Vector Float)               -- theta (weight vector)
    -> Acc (Matrix Float)               -- X (data matrix)
    -> Acc (Vector Float)               -- y (labels)
    -> Exp Float                        -- c (certain identification class)
    -> Exp Float                        -- lambda (learning rate)
    -- -> Exp                          -- repeat factor? i forget why i wrote this
    -> (Acc (Vector Float), Acc (Vector Float)) -- j, theta for c
fmincg theta xs ys c lambda = 
    let
        (f10, df10) = lrCostFunction theta xs yc lambda
        -- yc :: Acc (Vector Float) 
        yc = yEqCFloatVec ys c
        s0 = A.map negate df10
        d10 = A.map negate $ A.sum (A.zipWith (*) s0 s0)        
        z10 = unit ((1::Exp Float)/(1 - (the d10))) -- z10 is acc(scal)?
        fX0 = fill (constant (Z :. 0)) (0 :: Exp Float) -- need empty array

        -- cs :: Acc (Vector Float) 
        -- cs = fill (shape ys) c -- don't know how to 'unlift' c from its Exp wrapper...??

        -- set up initial values
        theta0 = A.zipWith (+) theta (A.map ((the z10) A.*) s0)
        (f20, df20) = lrCostFunction theta0 xs yc lambda
        d20 = A.sum $ A.zipWith (*) df20 s0
        f30 = f10
        d30 = d10
        z20 = unit (0 :: Exp Float) -- dummy value...
        z30 = A.map negate z10
        m0 = unit (50 :: Exp Int) -- max M?
        limit0 = unit ((-1) :: Exp Float)
        
        -- call loops now
        (theta', d2', d3', f2', f3', z1', z2', z3') = outerLoop theta0 s0 d10 d20 d30 f10 f20 f30 z10 z20 z30 xs ys lambda m0
        (theta_, fX_) = handleSuccess theta' d10 f10 f2' z1' df10 df20 fX0
        -- issue: must get df2 out of loops as it changes values for handleSuccess -> non issue as loop only goes through once and df2 is discarded?
    in
    (theta_, fX_)


handleSuccess :: 
       Acc (Vector Float) -- theta
    -> Acc (Scalar Float) -- d1
    -> Acc (Scalar Float) -- f1
    -> Acc (Scalar Float) -- f2
    -> Acc (Scalar Float) -- z1
    -> Acc (Vector Float) -- df1
    -> Acc (Vector Float) -- df2
    -> Acc (Vector Float) -- fX (array of costs) not actually used?
    -> ( Acc (Vector Float) -- old theta
       , Acc (Vector Float) ) -- fX (accum cost array?)
handleSuccess theta0 d10 f10 f20 z10 df10 df20 fX0 =
    let
        f11 = f20
        fX_ = fX0 A.++ (reshape (constant (Z:.(1::Int))) f10) -- update cost array?
        s1 = A.zipWith A.subtract x df20      -- Polack-Ribiere direction
        x = multScalerVector ((the dividend)/(the divisor)) s1
        dividend = A.sum $ A.zipWith (-) (A.zipWith (*) df20 df20) (A.zipWith (*) df10 df20)
        divisor = A.sum (A.zipWith (*) df10 df10) 
        df11 = df20
        df21 = df10
        d21 = the (A.sum (A.zipWith (*) df11 s1))
        s2 = (d21 A.> 0) 
            ?| ( A.map negate df11 , s1 ) 
        d22 = (d21 A.> 0) 
            ?| ( A.map negate (A.sum (A.zipWith (*) s2 s2)), unit d21)
        z11 = A.zipWith (*) z10 (unit (A.min 100 ((the d10)/(A.subtract (the d22) 2.225073858507201e-308)))) -- realmin == 2.225073858507201e-308
        d11 = d22 -- dunno why this is needed
    in
    (theta0, fX_) -- return (J/cost, grad)
    -- ignoring non-successful cases by assumption without proof that everything's peachy

outerLoop :: 
       Acc (Vector Float) -- theta
    -> Acc (Vector Float) -- s == -df1
    -> Acc (Scalar Float) -- d1 slope
    -> Acc (Scalar Float) -- d2
    -> Acc (Scalar Float) -- d3
    -> Acc (Scalar Float) -- f1 cost
    -> Acc (Scalar Float) -- f2
    -> Acc (Scalar Float) -- f3
    -> Acc (Scalar Float) -- z1
    -> Acc (Scalar Float) -- z2
    -> Acc (Scalar Float) -- z3
    -> Acc (Matrix Float) -- xs
    -> Acc (Vector Float) -- ys
    -> Exp Float          -- lambda
    -- -> Acc (Scalar Float) -- limit
    -> Acc (Scalar Int)   -- M (max 50)
    -> (  Acc (Vector Float) -- new theta
        -- , Acc (Vector Float) -- df2 -- FIX THIS
        , Acc (Scalar Float) -- d2
        , Acc (Scalar Float) -- d3
        , Acc (Scalar Float) -- f2
        , Acc (Scalar Float) -- f3
        , Acc (Scalar Float) -- z1
        , Acc (Scalar Float) -- z2
        , Acc (Scalar Float) ) -- z3
outerLoop theta0 s d10 d20 d30 f10 f20 f30 z10 z20 z30 xs ys lambda m0 = 
-- because d3 = d1
-- s = -df1
-- limit = z1
    let
        -- innerWhile initially once
        initial :: Acc (Vector Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Int, Scalar Float)
        initial =
            let 
                (theta1, d21, f21, z11, z21, z31, m1, limit1) = innerLoop s xs ys lambda d10 f10 d20 f20 f30 z10 z20 z30 m0 theta0 limit0
                limit0 = unit (-1 :: Exp Float)
          in
          lift (theta1, d10, d21, d30, f10, f21, f30, z11, z21, z31, m1, limit1)

        -- loop condition
        cond :: Acc (Vector Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Int, Scalar Float)
             -> Acc (Scalar Bool)
        cond args =
          let _theta:: Acc (Vector Float)
              _d3, _f3, _z2, _z3, _limit :: Acc (Scalar Float)
              (_theta, d1, d2, _d3, f1, f2, _f3, z1, _z2, _z3, m, _limit) = unlift args
          in
          A.zipWith6 outerLoopCondition f1 f2 z1 d1 d2 m        

        -- loop body (continue while 'cond' evaluates to True)
        body :: Acc (Vector Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Int, Scalar Float)
             -> Acc (Vector Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Int, Scalar Float)
        body args =
          let
              z2' :: Acc (Scalar Float) -- TLM: unused??
              (theta', d1', d2', d3', f1', f2', f3', z1', z2', z3', m', limit') = unlift args
              m_                                                                = A.map (A.subtract 1) m'
              (theta'', df2_, d2'', d3_, f2'', f3_, z1'', z2'', z3'')           = outerWhileFunction theta' s (the d2') (the d3') (the f2') (the f3') (the z1') (the z3') xs ys lambda (the limit')
              (theta_, d2_, f2_, z1_, z2_, z3_, m__, limit_)                    = innerLoop s xs ys lambda d1' f1' d2'' f2'' f3_ z1'' z2'' z3'' m_ theta'' limit'
          in
          lift (theta_, d1', d2_, d3_, f1', f2_, f3_, z1_, z2_, z3_, m__, limit_)

        -- return just the interesting results of the loop.
        -- extra type signatures necessary for things we don't care about due to
        -- use of 'unlift'
        _d1', _f1', _limit' :: Acc (Scalar Float)
        _m' :: Acc (Scalar Int)
        (theta', _d1', d2', d3', _f1', f2', f3', z1', z2', z3', _m', _limit') = unlift $ awhile cond body initial
    in
    (theta', d2', d3', f2', f3', z1', z2', z3')


innerLoop :: 
       Acc (Vector Float) -- s
    -> Acc (Matrix Float) -- xs
    -> Acc (Vector Float) -- ys
    -> Exp Float          -- lambda 
    -> Acc (Scalar Float) -- Exp Float -- d1
    -> Acc (Scalar Float) -- Exp Float -- f1 
    -> Acc (Scalar Float) -- d2 -- changes from here
    -> Acc (Scalar Float) -- f2
    -> Acc (Scalar Float) -- f3
    -> Acc (Scalar Float) -- z1
    -> Acc (Scalar Float) -- z2
    -> Acc (Scalar Float) -- z3
    -> Acc (Scalar Int) -- M (max loop count at 50)
    -> Acc (Vector Float) -- theta
    -> Acc (Scalar Float) -- limit
    -> (  Acc (Vector Float) -- new theta
        , Acc (Scalar Float) -- new d2
        , Acc (Scalar Float) -- new f2
        , Acc (Scalar Float) -- new z1
        , Acc (Scalar Float) -- new z2
        , Acc (Scalar Float) -- new z3
        , Acc (Scalar Int)   -- new m
        , Acc (Scalar Float) ) -- new limit
innerLoop s xs ys lambda d1 f1 d2 f2 f3 z1 z2 z3 m theta limit =
    let
        old = lift (theta, d2, f2, f3, z1, z2, z3, m, limit)
        new = awhile
                (\args -> A.zipWith6 innerLoopCondition f1 (args^._3) (args^._4) d1 (args^._2) (args^._8))
                (\args ->
                    let 
                        (theta', d2', f2', f3', z1', z2', z3', m', limit') = unlift args :: (Acc (Vector Float), Acc (Scalar Float), Acc (Scalar Float), Acc (Scalar Float), Acc (Scalar Float), Acc (Scalar Float), Acc (Scalar Float), Acc (Scalar Int), Acc (Scalar Float))
                        m_ = A.map (A.subtract 1) m'
                        (theta_, df2_, d2_, f2_, z1_, z2_, z3_, limit_) =  innerWhileFunction theta' s (the d1) (the d2') (the d1) (the f1) (the f2') (the f3') (the z1') (the z2) (the z3') xs ys lambda
                    in 
                    lift (theta_, d2_, f2_, f3', z1_, z2_, z3_, m_, limit_) )
                    -- :: Acc (Vector Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Float, Scalar Int))
                    -- don't need this anymore because function is complete! (no more scaffolding '')b
                old
    in
    (new^._1, new^._2, new^._3, new^._5, new^._6, new^._7, new^._8, new^._9)


outerWhileFunction :: 
       Acc (Vector Float) -- theta
    -> Acc (Vector Float) -- s == -df1
    -> Exp Float          -- d2
    -> Exp Float          -- d3
    -> Exp Float          -- f2
    -> Exp Float          -- f3
    -> Exp Float          -- z1
    -> Exp Float          -- z3
    -> Acc (Matrix Float) -- xs
    -> Acc (Vector Float) -- ys
    -> Exp Float          -- lambda
    -> Exp Float          -- limit
    -> (  Acc (Vector Float) -- new theta
        , Acc (Vector Float) -- df21
        , Acc (Scalar Float) -- d2
        , Acc (Scalar Float) -- d3
        , Acc (Scalar Float) -- f2
        , Acc (Scalar Float) -- f3
        , Acc (Scalar Float) -- z1
        , Acc (Scalar Float) -- z2
        , Acc (Scalar Float) ) -- z3
outerWhileFunction theta0 s d20 d30 f20 f30 z10 z30 xs ys lambda limit = 
    let 
        z21 = cubicExtrapolate d20 d30 f20 f30 z10 z30 limit
        f31 = f20 -- f3 = f2
        d31 = d20 -- d3 = d2 
        z31 = z21 -- z3 = -z2
        z11 = z10 + z21 -- z1 = z1 + z2
        theta1 = A.zipWith (+) theta0 (multScalerVector z21 s) -- X = X + z2*s
        (f21, df21) = lrCostFunction theta0 xs ys lambda -- [f2 df2] = eval(argstr);
        d21 = A.sum $ A.zipWith (*) df21 s -- d2 = df2'*s;
    in
    (theta1, df21, d21, unit d31, f21, unit f31, unit z11, unit z21, unit z31)


innerWhileFunction :: 
       Acc (Vector Float) -- theta
    -> Acc (Vector Float) -- s == -df1
    -> Exp Float          -- slope d1
    -> Exp Float          -- d2
    -> Exp Float          -- d3
    -> Exp Float          -- cost f1
    -> Exp Float          -- f2
    -> Exp Float          -- f3
    -> Exp Float          -- z1
    -> Exp Float          -- z2
    -> Exp Float          -- z3
    -> Acc (Matrix Float) -- xs
    -> Acc (Vector Float) -- ys
    -> Exp Float          -- lambda
    -> (  Acc (Vector Float) -- new theta
        , Acc (Vector Float) -- df21
        , Acc (Scalar Float) -- d2
        , Acc (Scalar Float) -- f2
        , Acc (Scalar Float) -- z1
        , Acc (Scalar Float) -- z2
        , Acc (Scalar Float) -- z3
        , Acc (Scalar Float) ) -- limit
innerWhileFunction theta0 s d10 d20 d30 f10 f20 f30 z10 z20 z30 xs ys lambda = 
    let 
        limit = z10
        z21  = (f20 A.> f10) 
            ? ( quadraticFit d30 f20 f30 z30, cubicFit d20 d30 f20 f30 z30 )
        z22 = (z21 A./= z21) -- if isNaN (z2) | isInf (z2)
            ? ( z30/2, z21 )   -- z2 = z3/2
        z23 = A.max (A.min z22 (0.1 * z30)) (0.9 * z30) -- z2 = max(min(z2, INT*z3),(1-INT)*z3)
        z11 = z10 + z23 -- z1 = z1 + z2;
        theta1 = A.zipWith (+) theta0 (multScalerVector z23 s) -- X = X + z2*s;
        (f21, df21) = lrCostFunction theta1 xs ys lambda -- [f2 df2] = eval(argstr);
        d21 = A.sum (A.zipWith (*) df21 s) -- d2 = df2'*s;
        z31 = A.subtract z30 z23; -- z3 = z3-z2;
    in
    (theta1, df21, d21, f21, unit z11, unit z23, unit z31, unit limit)
    

-- (f2 A.> (f1 + z1 * 0.01 * d1)) A.|| (d2 A.> -0.5 * d1)
innerLoopCondition :: Exp Float -- f1
    -> Exp Float -- f2
    -> Exp Float -- z1
    -> Exp Float -- d1
    -> Exp Float -- d2
    -> Exp Int   -- M
    -> Exp Bool
innerLoopCondition f1 f2 z1 d1 d2 m = (f A.|| s)
    where
        -- (f1, f2, z1, d1, d2, m) = unlift args
        f = (f2 A.> (f1 + z1 * 0.01 * d1))
        s = ((d2 A.> -0.5 * d1) A.&& lift (m A.> 0)) 


-- (f2 A.> (f1 + z1 * 0.01 * d1)) A.|| (d2 A.> -0.5 * d1)
outerLoopCondition :: Exp Float -- f1
    -> Exp Float -- f2
    -> Exp Float -- z1
    -> Exp Float -- d1
    -> Exp Float -- d2
    -> Exp Int   -- M
    -> Exp Bool
outerLoopCondition f1 f2 z1 d1 d2 m = (f A.|| s A.|| t)
    where
        -- if f2 > f1+z1*RHO*d1 | d2 > -SIG*d1 | d2 > SIG*d1 | M == 0
        f = (f2 A.> (f1 + z1 * 0.01 * d1)) -- failure
        s = ((d2 A.> -0.5 * d1) A.|| lift (m A.== 0)) -- failure
        t = (d2 A.> 0.5 * d1) -- success


cubicFit :: Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float
cubicFit d2 d3 f2 f3 z3 = z2
    where
        a = 6*(f2 - f3)/z3 + 3*(d2 + d3)
        b = 3*(f3 - f2) - z3*(d3 + 2*d2)
        z2 = (P.sqrt (b*b - a*d2*z3*z3) - b)/a


quadraticFit :: Exp Float -> Exp Float -> Exp Float -> Exp Float -> Exp Float
quadraticFit d3 f2 f3 z3 = z3 - (0.5*d3*z3*z3)/(d3*z3 + f2 - f3)


nnCostFunction ::
       Acc (Matrix Float)               -- input theta matrix (25x401) -input_num 400
    -> Acc (Matrix Float)               -- hidden theta matrix (10x26) -hidden_num 25
    -> Exp Int                          -- num of labels
    -> Acc (Matrix Float)               -- X (data matrix) in the form [1 X] (5000x401)
    -> Acc (Vector Float)               -- y (labels)
    -> Exp Float                        -- lambda
    -> ( Acc (Scalar Float)             -- J (cost)
       , Acc (Vector Float) )           -- final theta
nnCostFunction theta1 theta2 n xs y lambda = 
    let
        Z :. h :. w = unlift (shape xs) :: Z :. Exp Int :. Exp Int

        toYs :: Acc (Vector Float) -> Acc (Matrix Float)
        toYs y = undefined
        -- make vector y into matrix Y

        ys :: Acc (Matrix Float)
        ys = toYs y

        -- feedforward
        a3 :: Acc (Matrix Float)
        a1 = xs -- (5000x401)
        z2 = mmult a1 (A.transpose theta1) -- (5000x401) x (401x25) = (5000 x 25) 
        a2 = (fill (constant (Z :. 5000 :. 1)) 1 :: Acc (Matrix Float)) A.++ 
             A.map sigmoid z2 -- (5000x26) -- this should be h...
        z3 = mmult a2 (A.transpose theta2) -- (5000x26) x (26x10) = (5000x10)
        a3 = A.map sigmoid z3 -- (5000x10)

        -- calculate cost J
        j :: Acc (Scalar Float)
        j = A.zipWith (+) regCost 
          $ A.sum 
          $ A.map (\x -> x / A.fromIntegral h)
          $ A.sum
          $ A.zipWith (-) fstMat sndMat
          where
            fstMat  = A.zipWith (*) (A.map negate ys) (A.map log a3)
            sndMat  = A.zipWith (\y a -> -y * (log a) - (1-y)*log(1-a)) ys a3
            regCost = A.sum
                    $ A.map (\x -> x * lambda/(2*(A.fromIntegral h)))
                      (A.zipWith (+) j1 j2)
            j1      = foldAll (+) 0 (A.zipWith (*) ttheta1 ttheta1)
            j2      = foldAll (+) 0 (A.zipWith (*) ttheta2 ttheta2)

        ttheta1 = A.tail theta1
        ttheta2 = A.tail theta2

        -- backpropagate to get gradients
        d3 = A.zipWith (-) a3 ys
        d2 = A.zipWith (*) 
             (mmult (transpose theta2) d3)
             ((fill (constant (Z :. 5000 :. 1)) 1 :: Acc (Matrix Float)) A.++ (sigmoidGradient z2))

        theta2grad = A.map (\x -> x/A.fromIntegral h) 
                   $ mmult d3 (transpose a2)
        theta1grad = A.map (\x -> x/A.fromIntegral h) 
                   $ transpose
                   $ mmult (transpose a1) (A.tail (transpose d2))

        -- add gradient regularisation
        theta1grad_ = A.zipWith (+) theta1grad 
                    $ A.map (\x -> lambda * x/A.fromIntegral h)
                      ((fill (constant (Z :. 25 :. 1)) 1 :: Acc (Matrix Float)) A.++ (A.tail theta1))
                      where
                        s = A.size theta1 -- height of array MUST FIX THIS!!!
        
        theta2grad_ = A.zipWith (+) theta2grad 
                    $ A.map (\x -> lambda * x/A.fromIntegral h)
                      ((fill (constant (Z :. 10 :. 1)) 1 :: Acc (Matrix Float)) A.++ (A.tail theta2))
                      where
                        s = A.size theta2 -- height of array MUST FIX THIS!!!

                   -- d2(2:end, :)

                   -- d2 = (100x50) -> d2 = 99x50
                   -- d2' = (50x100) -> transpose (tail (transpose d2) (50x99)) (99x50) * (transpose a1 (50x500)) (99x500)

                   -- tranpose (transpose a1 (500x50) * tail (transpose d2) (50x99))
        
        grads = flatten theta1grad_ A.++ flatten theta2grad_

        -- g = exp(-z) ./ ((1.0 + exp(-z)) .^ 2)
        -- sigmoidGradient can also take in a Vector...
        sigmoidGradient :: Acc (Matrix Float) -> Acc (Matrix Float)
        sigmoidGradient a = A.map (\x -> exp(-x) / (1.0 + exp(-x))P.^2) a

    in
    (j, grads)

-- lrCostFunction(theta, X, y, lambda) = [J, grad]
lrCostFunction ::
       Acc (Vector Float)               -- theta (weight vector)
    -> Acc (Matrix Float)               -- X (data matrix)
    -> Acc (Vector Float)               -- y (labels)
    -> Exp Float                        -- lambda (learning rate)
    -> (Acc (Scalar Float), Acc (Vector Float))
lrCostFunction theta xs ys lambda = (unit jreg, grad)  -- lift :: (Acc (Scalar Float), Acc (Vector Float)) -> Acc (Scalar Float, Matrix Float)
  where
    temp :: Acc (Vector Float) -- theta with theta[0] = 0
    temp = (enumFromN (constant (Z:.1)) 0) A.++ (A.tail theta)

    -- grad = (1/m) * (xs' * (h .- y) + lambda * theta)
    grad :: Acc (Vector Float)
    grad = A.map (\x -> x / A.fromIntegral m) 
         $ A.zipWith (+) (multScalerVector lambda theta) $ fold (+) 0 (A.zipWith (*) (transpose xs) hy)

    -- turn (h .- y) into a matrix for grad
    -- multiply vector (h.-y) into a matrix of height w
    hy :: Acc (Matrix Float)
    hy = A.replicate (lift (Z :. w :. All)) (A.zipWith A.subtract hyp ys)

    m :: Exp Int
    m = A.length ys

    -- n :: Exp Int
    -- n = A.length xs

    Z :. h :. w = unlift (shape xs) :: Z :. Exp Int :. Exp Int

    -- learning rate
    -- lambda :: Exp Float
    -- lambda = (0.1 :: Exp Float)

    jreg :: Exp Float
    jreg = the reg + the j

    -- error accumulation?
    -- j = (1/m) * sum(-y.*(log(hypothesis)) - (1-y).*log(1-hypothesis))
    j :: Acc (Scalar Float)
    j = A.map (\x -> x / A.fromIntegral m)
      $ A.sum
      $ A.zipWith (\h y -> -y * (log h) - (1 - y) * log (1 - h)) hyp ys

    reg :: Acc (Scalar Float) -- regularisation constant (lambda/(2*m)*sum(temp.^2))
    reg = A.map (\x -> lambda * x / A.fromIntegral (2*m)) (A.sum (A.zipWith (*) temp temp))

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

    -- multiply matrix X with vector theta to get new vector theta
    -- hypothesis = sigmoid (X * theta)
    hyp :: Acc (Vector Float) -- h = X * theta
    hyp = A.map (sigmoid) (fold (+) 0 (A.zipWith (*) xs tt))


multScalerVector :: Exp Float -> Acc (Vector Float) -> Acc (Vector Float)
multScalerVector f v = A.zipWith (*) f' v
    where
        f' = A.replicate (lift (Any :. h)) (unit f)
        Z :. h = unlift (shape v) :: Z :. Exp Int


sigmoid :: Exp Float -> Exp Float
sigmoid z = 1.0 / (1.0 + exp(-z))


-- negateVector :: Acc (Vector Float) -> Acc (Vector Float)
-- negateVector f = A.map negate f


-- negateScalar :: Acc (Scalar Float) -> Acc (Scalar Float)
-- negateScalar s = A.map negate s


yEqCFloatVec :: Acc (Vector Float) -> Exp Float -> Acc (Vector Float)
yEqCFloatVec ys c = A.map (A.fromIntegral . boolToInt . (c A.==)) ys


cubicExtrapolate :: 
       Exp Float      -- d2
    -> Exp Float      -- d3
    -> Exp Float      -- f2
    -> Exp Float      -- f3
    -> Exp Float      -- z1
    -> Exp Float      -- z3
    -> Exp Float      -- limit
    -> Exp Float      -- z2
cubicExtrapolate d2 d3 f2 f3 z1 z3 limit =
    if det A.< 0 A.|| A.isNaN z2 A.|| A.isInfinite z2 A.|| z2 A.< 0
    then if limit A.< 0.5
        then z1 * (3 - 1)
        else (limit - z1)/2
    else if (limit A.> 0.5) A.&& (z2 + z1) A.> limit
        then (limit - z1)/2
    else if (limit A.< 0.5) A.&& (z2 + z1) A.> z1 * 3
        then z1 * 2 -- (EXT-1.0)
    else if (z2 A.< -z3 * 0.1)
        then -z2 * 0.1
    else if (limit A.> -0.5) A.&& (z2 A.< (limit-z1)*0.9) -- (limit-z1)*(1.0-INT)
        then (limit - z1)*(0.9) -- (1.0 - INT)
    else
        z2
    where 
        a   = 6*(f2 - f3)/z3 + 3*(d2 + d3)
        b   = 3*(f3 - f2) - z3*(d3 + 2*d2)
        det = b*b - a*d2*z3*z3
        z2  = -d2 * z3 * z3 / (b + sqrt det)
    -- if ~isreal(z2) | isnan(z2) | isinf(z2) | z2 < 0   % num prob or wrong sign?
    --     if limit < -0.5                               % if we have no upper limit
    --         z2 = z1 * (EXT-1);                 % the extrapolate the maximum amount
    --     else
    --         z2 = (limit-z1)/2;                                   % otherwise bisect

        -- z2  = (b A.< 0) -- if ~isreal(z2)
        --     ? ( z2' , z2'' ) 
        -- z2' = (limit A.< -0.5)
        --     ? ( z1 * (3.0 - 1.0), (limit - z1)/2 )
        -- z2_ = (-d2*z3*z3)/(b + P.sqrt (b*b - a*d2*z3*z3))
        -- z2'' = (A.isNaN z2_ A.|| A.isInfinite z2_ A.|| z2_ A.< 0)
        --      ? ( z2', z2_ )