{-
Syntax and Implementation of Boolean Expressions
================================================
-}

module BoolExp where

import Pi
import qualified Data.Map.Strict as M

data BoolExp
  = BVar Name
  | BVal Bool
  | BoolExp :&&: BoolExp
  | BoolExp :||: BoolExp
  | Not BoolExp
  deriving Show

-- Environments for interpreting boolean expressions
type BEnv = M.Map Name Bool

-- TASK!!!
-- compileBExp tchan fchan b
-- returns a process p that when juxtaposed with a compatible environment
-- sends a message on tchan if the boolean expression evaluates to true
-- sends a message on fchan if the boolean expression evaluates to false

compileBExp :: Name -> Name -> BoolExp -> Pi
compileBExp tchan fchan (BVar name)  = Out name unitE 
compileBExp tchan fchan (BVal bool)  = if bool then Out tchan unitE else Out fchan unitE
compileBExp tchan fchan (b1 :&&: b2) = compileBExp tchan fchan $ Not $ b1' :||: b2' 
   where b1' = compileBExp tchan fchan $ Not b1
         b2' = compileBExp tchan fchan $ Not b2
compileBExp tchan fchan (b1 :||: b2) = New tchan' unitT $ New fchan' unitT $ or_p
  where tchan' = tchan ++ "t"
        fchan' = fchan ++ "f"
        b1_p = (compileBExp tchan' fchan' b1)
        b2_p = (compileBExp tchan' fchan' b2)
        true = Inp tchan' unitP $ Out tchan unitE
        false = Inp fchan' unitP $ Inp fchan' unitP $ Out fchan unitE 
        or_p = (b1_p :|: b2_p) :|: (true :|: false)  
compileBExp tchan fchan (Not b)      = compileBExp fchan tchan b 



-- TASK!!
-- compile a boolean variable environment into a process that
-- communicates with a compiled Boolean expression containing free
-- variables from the environment
compileBExpEnv :: BEnv -> Pi -> Pi
compileBExpEnv benv p = undefined

startBool :: BEnv -> BoolExp -> IO ()
startBool benv bexp =
  start pi
    where
      tchan = "t"
      fchan = "f"
      pi = New tchan unitT $
           New fchan unitT $
           compileBExpEnv benv (compileBExp tchan fchan bexp) :|:
           Inp tchan unitP (printer "true") :|:
           Inp fchan unitP (printer "false")
