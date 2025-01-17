{-
Compiling the Lambda Calculus
====================================

Sending channels through channels is an interesting model, but how many
algorithms can we really implement this way?  It turns out that the
pi-calculus can implement any computable function.

We could demonstrate this by compiling the untyped Lambda Calculus to the
untyped Pi Calculus but since we have a typed Pi Calculus as a target,
we will start with a typed Lambda Calculus.  It isn't Turing Complete,
but it's pretty cool nonetheless!

-}

module Lam where

import Pi hiding (Gamma)
import Data.Map (Map, (!))
import qualified Data.Map as Map
import Data.IORef

-- The typed lambda calculus:

data LTyp
  = LTUnit
  | LTArrow LTyp LTyp
  deriving (Eq, Show)

data Lam
  = LUnit              -- unit:  ()
  | LVar Name          -- variables:  x
  | LAbs Name LTyp Lam -- lambda abstraction: \x:t.e
  | LApp Lam Lam        -- application:  f :@: e executes f on argument e
  | LEff (IO ()) Lam   -- run an effectful computation of your choice
                       -- see printL below for a useful example

instance Show Lam where
  show LUnit = "()"
  show (LVar x) = x
  show (LAbs x t e) = "(\\" ++ x ++ " : " ++ (show t) ++ ". " ++ (show e) ++ ")"
  show (LApp e1 e2) = (show e1) ++ "(" ++ (show e2) ++ ")"
  show (LEff _ e) = "LEff _ (" ++ (show e) ++ ")"

-- Useful abbreviations:

-- printL s e is a lambda expression that prints s and then executes e
printL :: String -> Lam -> Lam
printL s e = LEff (putStr $ s ++ "\n") e

-- Environments for type checking Lambda expressions
type Gamma = Map Name LTyp

-- Lambda expression type checker
typeOf :: Gamma -> Lam -> Either String LTyp
typeOf g LUnit = pure LTUnit
typeOf g (LVar x) =
  case Map.lookup x g of
    Just t -> pure t
    Nothing -> Left $ "no such variable " ++ x
typeOf g (LAbs x t1 e) = LTArrow t1 <$> typeOf (Map.insert x t1 g) e
typeOf g (LApp e1 e2) = do
  t1 <- typeOf g e1
  t2 <- typeOf g e2
  case t1 of
    LTArrow t11 t12 | t2 == t11 -> pure t12
    LTArrow t11 _ -> Left "type mismatch in application"
    _ -> Left "applied non-function"
typeOf g (LEff a e) = typeOf g e

-- type check closed expressions
-- check :: Lam -> IO Bool
-- check e =
--   case typeOf M.empty e of
--     Good x -> return True
--     Bad s -> putStr s >> return False

-- Linear lambda expression type checker
lintypeOf :: Gamma -> Lam -> Either String (Gamma, LTyp)
lintypeOf g LUnit = pure (g, LTUnit)
lintypeOf g (LVar x) =
  case Map.lookup x g of
    Just t -> pure (Map.delete x g, t)
    Nothing -> Left $ "no such variable " ++ x
lintypeOf g (LAbs x t1 e) = do
  (g',t2) <- lintypeOf (Map.insert x t1 g) e
  if Map.member x g'
    then Left $ "variable " ++ x ++ " not used"
    else pure (case Map.lookup x g of { Just tx -> Map.insert x tx g' ; Nothing -> g' },
               LTArrow t1 t2)
lintypeOf g (LApp e1 e2) = do
  (g1, t1) <- lintypeOf g e1
  (g2, t2) <- lintypeOf g1 e2
  case t1 of
    LTArrow t11 t12 | t11 == t2 -> pure (g2, t12)
    LTArrow _ _ -> Left $ "type mismatch in application"
    _ -> Left $ "applied non-function"
lintypeOf g (LEff a e) = lintypeOf g e

-- linear type check closed expressions
lincheck :: Lam -> IO Bool
lincheck e =
  case lintypeOf Map.empty e of
    Right (g,t) -> return $ Map.null g
    Left s -> putStrLn s >> return False

nameGenerator :: IORef Integer -> IO Name
nameGenerator counter = do
  n <- readIORef counter
  modifyIORef' counter (+1)
  return ("x" ++ show n)

-- TASK!
-- Implement your lambda calculus to pi calculus compiler here!

typeTrans :: LTyp -> Typ
typeTrans LTUnit = unitT
typeTrans (LTArrow t1 t2) = TTup [TChan (typeTrans t1), TChan (typeTrans t2)]

-- compiler goes here
-- note that your first argument is a name generator, to come up with fresh channel names
compileLam :: IO Name -> Name -> Gamma -> Lam -> IO (LTyp, Pi)
compileLam gen res_channel gamma LUnit = 
  do let p = Out res_channel unitE
     let t = LTUnit 
     return (t,p)
compileLam gen res_channel gamma (LVar varname) =
  do let t = if Map.member varname gamma
             then gamma Map.! varname
             else error $ "Varname : " ++ varname ++ " not not stored in context : " ++ show gamma
     let p = Out res_channel (EVar varname)
     return (t,p)
compileLam gen res_channel gamma labs@(LAbs varname i_type e) = 
  do [io,i,o] <- sequence [gen,gen,gen]
     (o_type,e_p) <- compileLam gen o gamma' e
     let share_io = Out res_channel $ ETup [(EVar i),(EVar o)] 
     let exec = Inp i (PVar varname) e_p
     let p = New i (TChan $ typeTrans i_type)
           $ New o (TChan $ typeTrans o_type)
           $ share_io :|: exec 
     let t = LTArrow i_type o_type 
     return (t,p)
     where gamma' = Map.insert varname i_type gamma 
compileLam gen res_channel gamma (LApp func arg) = 
  do [i,o,io,res] <- sequence [gen,gen,gen,gen]
     (func_t,func_p) <- compileLam gen io gamma func
     (arg_t,arg_p) <- compileLam gen i gamma arg
     let send_res = (Inp o (PVar res) $ Out res_channel (EVar res))
     let exec_func = Inp io (PTup [(PVar i),(PVar o)])
              $ arg_p :|: send_res
     let p = New io (TChan $ typeTrans func_t)
           $ func_p :|: exec_func  
     let t = (\ (LTArrow _ typ) -> typ) func_t
     return (t,p)
compileLam gen res_channel gamma (LEff io e) =  
  do (e_t,e_p) <- compileLam gen res_channel gamma e
     let p = Embed (envAction io) e_p 
     return (e_t,p)

envAction :: IO () -> Env -> IO ()
envAction io _ = io
startLam :: Lam -> IO ()
startLam e = do
  b <- lincheck e
  if not b
    then putStr "Source program does not type check.\n"
    else do
      r <- newIORef 0
      let fresh = nameGenerator r
      n <- fresh
      (t,pi) <- compileLam fresh n Map.empty e
      let wrap = New n (TChan $ typeTrans t) $ pi :|: Inp n Wild (printer "done!")
      case check wrap of
        Left err -> do
          putStrLn $ "Translated program does not type check.  Program:"
          putStrLn $ show wrap
          putStrLn $ "Error: \n" ++ err
        Right () -> start wrap
