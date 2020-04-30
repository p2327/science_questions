module Main where

import Prelude
import Affjax as AX
import Affjax.ResponseFormat as ResponseFormat
import Data.Array (mapWithIndex)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff.Class (class MonadAff, liftAff)
import Halogen as H
import Halogen.Aff as HA
import Halogen.HTML (ClassName(..))
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Themes.Bootstrap4 as B
import Halogen.VDom.Driver (runUI)
import Simple.JSON as SimpleJSON

import Halogen.HTML (ClassName(..))                -- As above
-- import Halogen.HTML.Properties (ButtonType(..)) -- Added to specify button properties
-- import Halogen.HTML.Properties as HP            -- As above
-- import Halogen.HTML (ClassName(..))             -- As above


-- Server url
questionServiceUrl :: String
questionServiceUrl = "http://localhost:8080/question"

-- Question type used for both JSON parsing and state
type Question
  = { questionText :: String
    , answers :: Array String
    , correctAnswer :: Int
    }

data Action
  = NewGame
  | ClickAnswer Int
  | NextQuestion
  | Toggle Boolean -- Added Toggle for handling button color change

data Status
  = WaitingForQuestion
  | HaveQuestion Question (Maybe Int)
  | Failure String

type State
  = { score  :: Int
    , status :: Status
    }

-- State of button
--type ButtonState
 -- = Boolean

{-
-- Query approach for button class change
data Query a
  = UpdateButtonState a
  | GetButtonState

-- Change class of button to handle color
-- Maybe I can just handle changing mkButton?
toggleButtonClass :: forall m. ButtonState -> H.ComponentHTML Action () m
toggleButtonClass isClicked =
    let
      toggleLabel = if isClicked then "clickedButton" else "notClickedButton"
    in
      HH.button
        [ HP.class_ $ ClassName toggleLabel
        , HE.onClick \_ -> Just Toggle
        ]
-}

-- Start out with no questions.
initialState :: State
initialState = { score: 0, status: WaitingForQuestion }

-- Helper function for creating buttons that trigger an action
mkButton :: forall a. String -> Action -> HH.HTML a Action
mkButton str act =
  --let
    --toggleLabel = if isClicked then "clickedButton" else "notClickedButton"
  HH.button
    [ -- HP.classes [ B.btnLg, B.btnBlock ]
      HE.onClick \_ -> Just act
    , HE.onClick \_ -> Just Toggle
    ]
    [ HH.text str ]

-- | Shows how to add event handling.
render :: forall m. State -> H.ComponentHTML Action () m
render s =
  let
    questionBlock = case s.status of
      WaitingForQuestion -> HH.text "Loading..."
      HaveQuestion question maybeAnswer ->
        let
          answerSummary = case maybeAnswer of
            Nothing -> []
            Just idx ->
              [ HH.div_
                  [ HH.text
                      $ if idx == question.correctAnswer then
                          "Correct"
                        else
                          "Incorrect"
                  ]
              ]
        in
          HH.div_
            $ [ HH.text question.questionText
              ]
            <> mapWithIndex (\idx txt -> HH.div_ 
                                          [ mkButton txt $ ClickAnswer idx ]) question.answers
            <> answerSummary
      Failure str -> HH.text $ "Failed: " <> str
  in
    HH.div [ HP.classes [ B.containerFluid ] ]
      [ HH.div [ HP.classes [ B.h1 ] ] [ HH.text "SciQs" ]
      , HH.div_ [ mkButton "New Game" NewGame ]
      , HH.div_ [ mkButton "Next Question" NextQuestion ]
      , HH.div_ [ HH.text $ "Score: " <> show s.score ]
      , questionBlock
      ]

{-- Evaluate input query
eval :: Query ~> H.ComponentDSL ButtonState Query Void m
eval (UpdateButtonState next) = do
  H.modify_ not
  pure next
eval (GetButtonState reply) = do
    reply <$> H.get -}

-- | Shows how to use actions to update the component's state
handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action () o m Unit
handleAction = case _ of
  NewGame -> do
    H.modify_ \s -> s { score = 0 }
    handleAction NextQuestion
  ClickAnswer idx ->
    H.modify_ \s -> case s.status of
      HaveQuestion q _ ->
        let
          points = if idx == q.correctAnswer then 1 else 0
        in
          s { status = HaveQuestion q (Just idx), score = s.score + points }
      _ -> s { status = Failure $ "Somehow clicked idx " <> show idx <> " when not in question display state" }
    -- Add action to change button color
  Toggle -> do
    H.modify_ \oldState -> not oldState
  NextQuestion -> do
    H.modify_ \s -> s { status = WaitingForQuestion }
    result <- liftAff $ AX.get ResponseFormat.string questionServiceUrl
    case result of
      Left err -> H.modify_ \s -> s { status = Failure $ "GET /api response failed to decode: " <> AX.printError err }
      Right response -> case SimpleJSON.readJSON response.body of
        Right (r :: Question) -> do
          H.modify_ \s -> s { status = HaveQuestion r Nothing }
        Left e -> H.modify_ \s -> s { status = Failure $ "Can't parse JSON. " <> show e }

component :: forall q i o m. MonadAff m => H.Component HH.HTML q i o m
component =
  H.mkComponent
    { initialState: const initialState
    , render
    , eval:
        H.mkEval
          $ H.defaultEval
              { handleAction = handleAction
              , initialize = Just NewGame
              }
    }

main :: Effect Unit
main =
  HA.runHalogenAff do
    body <- HA.awaitBody
    runUI component unit body