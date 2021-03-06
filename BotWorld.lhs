\documentclass[a4paper]{article}
%include polycode.fmt

\usepackage{listings}
\usepackage[english]{babel}
\usepackage[utf8x]{inputenc}
\usepackage{amsmath}
\usepackage{graphicx}
\usepackage{appendix}
\usepackage{mdwlist}

%format <*> = "\mathop{<\!\!\ast\!\!>}"
%format <$> = "\mathop{<\!\!\$\!\!>}"

\title{Botworld 1.0\\(Technical Report)}

\author{Nate Soares, Benja Fallenstein}

\date{\today}

\begin{document}
\maketitle

\tableofcontents
\newpage

\section{Motivation}

This report introduces \emph{botworld}, a cellular automaton used for studying self-modifying agents.

Most formal frameworks for studying self-modifying agents split the universe into an agent and an environment. The agent interacts with the environment only via discrete input and output channels.

Such formalisms are perhaps ill-suited for real self-modifying agents, which are embedded within their environments. Indeed, the agent/environment separation is somewhat reminiscent of cartesian dualism: any agent built using such a framework does not model itself as part of its environment.

Intuitively, this separation is not a fatal flaw, but merely a tool for simplifying the discussion. We should be able to remove this ``cartesian'' assumption from formal models of intelligence. Botworld is a tool for probing this intuition: it provides a concrete world containing agents that we wish to act intelligently, and allows us to study what happens when the cartesian barier between an agent and its environment begins to break down.

As it turns out, many interesting obstacles arise when agents are embedded in an environment. For example, agents whose source code may be read may be subjected to Newcomb-like problems (with entities that simulate the agent's actions and choose their actions accordingly).

Descision theoretical tools for solving such problems alrdeady exist (such as Vladimir Slepnev's formalism of updateless decision theory); botworld provides an environment where we can actually build the games, program the agents, and run the system.

Furthermore, certain obstacles to self-reference arise when non-cartesian agents attempt to achieve condfidence in their future actions. Some of these issues are raised in the \emph{Tiling Agents} paper by Yudkowsky and Herreshoff; botworld gives us a concrete environment in which we can examine them.

One of the primary benefits of botworld is \emph{concreteness}: when working with abstract problems of self-reference, it is often very useful to see a discrete game in a fully specified world that directly exhibits the obstacle under consideration. Botworld makes it easier to visualize these obstacles.

Conversely, botworld also makes it easier to visualize suggested agent architectures, which in turn makes it easier to visualize potential problems and probe the architecture for edge cases.

Finally, botworld is a tool for communicating. It is our hope that botworld will help others understand the varying formalisms for self-modifying agents by giving them a concrete way to visualize such architectures being implemented. Furthermore, botworld gives us a concrete way to illustrate various obstacles, by implementing botworld games in which the obstacles arise.

For example, consider an agent that is searching for a strategy in some game, and wants to do at least as well as some fallback strategy. In a traditional cartesian framework, the agent may adopt a simple architecture that searches for strategy/proof pairs where the proof proves that the strategy does better than the fallback.

In a non-cartesian environment, such a proof will not suffice. Consider, for example, a \emph{stupidity rewarding} agent which reads source code and dispenses large rewards to agents with the program ``do nothing ever''.

An agent in the same world as the stupidity rewarder with a fallback strategy of ``do nothing ever'' will fail to self-modify into an agent that does nothing ever, because it falsely believes that its proof-searching strategy will do at least as well as its fallback strategy. This agent fails to realize that the stupidity rewarder can distinguish between robots that \emph{actually} do nothing ever and robots that search for strategies (with ``do nothing ever'' as a fallback).

This problem is somewhat abstract and perhaps difficult to visualize---but in botworld, we can \emph{actually build a game} with a stupidity rewarder and a proof-searching robot, and see how the proof searcher goes wrong.

Botworld has helped us gain a deeper understanding of varying formalisms for self-modifying agents and the obstacles they face. It is our hope that botworld will help others more concretely understand these issues as well.

\section{Overview}

Botworld is a high level cellular automaton: the contents of each cell can be quite complex. Indeed, cells may house robots with register machines, which are run for a fixed amount of time in each cellular automaton step. A brief overview of the cellular automaton follows. Afterwards, we will present the details along with a full implementation in Haskell.

Botworld is a cellular automaton with \emph{robots} and \emph{items}. The robots navigate a grid of cells (some of which may be impassable walls) and manipulate the items. Some items are quite useful: for example, shield items can protect robots from aggressors. Other items are intrinsically valuable, though the values of various items depends upon the game being played.

Among the items are \emph{robot parts}, which the robots can use to construct other robots. Robots may also be broken down into their component parts (hence the necessity for shields). Thus, robots in botworld are quite versatile: a well-programmed robot can reassemble its enemies into allies or construct a robot horde.

Because robots are transient objects, it is important to note that players are not robots. Many games begin by allowing each player to specify the initial state of a single robot, but clever players will write programs that soon distribute themselves across many robots or construct fleets of allied robots. Thus, botworld games are not scored depending upon the actions of the robot. Instead, each player is assigned a home square (or squares), and botworld games are scored according to the contents of the home squares at the end of the game.

Robots cannot see the contents of robot register machines by default, though robots \emph{can} execute an inspection to see the precise state of another robot's register machine. This can lead to interesting games, particularly when the inspecting robot is powerful enough to simulate the targeted robot in full.

It is important to note that there are two different notions of time in botworld. The cellular automaton evolution proceeds in discrete steps according to the rules described below. During each cellular automaton step, the machines inside the robots are run for some finite number of ticks.

Like any cellular automaton, botworld updates in discrete \emph{steps} which apply to every cell. Each cell is updated using only information from the cell and its immediate neighbors. Roughly speaking, the step function proceeds in the following manner for each individual square:

\begin{enumerate*}
  \item The output register of the register machine of each robot in the square is read to determine the robot's \emph{command}. Note that robots are expected to be initialized with their first command in the output register.
  \item The commands are used in aggregate to determine the robot \emph{actions}. This involves checking for conflicts and invalid commands.
  \item The item list is updated according to the robot actions. Items that have been lifted or used to create robots are removed, items that have been dropped are added.
  \item Robots incoming from neighboring squares are added to the robot list.
  \item Created robots are added to the robot list.
  \item The input registers are set on all robots. Robot input includes a list of all robots in the square (including exiting, entering, destroyed, and created robots), the actions that each robot took, and the updated item list.
  \item Robots that have exited the square or that have been destroyed are removed from the robot list.
  \item All remaining robots have their register machines executed (and are expected to leave a command in the output register.)
\end{enumerate*}

These rules allow for a wide variety of games, from NP-hard knapsack packing games to difficult Newcomb-like games such as a variant of the Parfit's hitchhiker problem (wherein a robot will drop a valuable item only if it, after simulating your robot, concludes that your robot will give it a less valuable item).

\section{Implementation}

This report is a literate Haskell file, so we must begin the code with the module definition and the Haskell imports.

\begin{code}
module BotWorld where
import Control.Applicative ((<$>), (<*>))
import Control.Monad (join)
import Control.Monad.Reader (Reader, asks)
import Data.List (delete, elemIndices, intercalate, sortBy)
import Data.List.Split (chunksOf)
import Data.Maybe (catMaybes, isJust, fromMaybe, mapMaybe)
import Data.Ord (comparing)
import Text.Printf (printf)
\end{code}

Botworld cells may be either walls (which are immutable and impassible) or \emph{squares}, which may contain both \emph{robots} and \emph{items} which the robots carry and manipulate. We represent cells using the following type:

\begin{code}
type Cell = Maybe Square
\end{code}

The interesting parts of botworld games happen in the squares.

\begin{code}
data Square = Square
  { robotsIn :: [Robot]
  , itemsIn :: [Item]
  } deriving (Eq, Show)
\end{code}

The ordering is arbitrary, but is used by robots to specify the targets of their actions: a robot executing the command |Lift 3| will attempt to lift the item at index |3| in the item list of its current square.

Botworld, like any cellular automaton, is composed of a grid of cells.

\begin{code}
type BotWorld = Grid Cell
\end{code}

We do not mean to tie the specification of botworld to any particular grid implementation: botworld grids may be finite or infinite, wrapping (pacman style) or non-wrapping. The specific implementation used in this report is somewhat monotonous, and may be found in Appendix~\ref{app:grid}.

\subsection{Robots}

Each robot can be visualized as a little metal construct on wheels, with a little camera on the front, lifter-arms on the sides, a holding area atop, and a register machine ticking away deep within.

\begin{code}
data Robot = Robot
  { frame :: Frame
  , inventory :: [Item]
  , processor :: Processor
  , memory :: Memory
  } deriving (Eq, Show)
\end{code}

The robot frame is colored (the robots are painted) and has a \emph{strength} which determines the amount of weight that the robot can carry in its inventory.

\begin{code}
data Frame = F { color :: Color, strength :: Int } deriving (Eq, Show)
\end{code}

The color is not necessarily unique, but may help robots distinguish other robots. In this report, colors are represented as a simple small enumeration. Other implementations are welcome to adopt a more fully fledged datatype for representing robot colors.

\begin{code}
data Color = Red | Orange | Yellow | Green | Blue | Violet | Black | White
  deriving (Eq, Ord, Enum)
\end{code}

The frame strength limits the total weight of items that may be carried in the robot's inventory. Every item has a weight, and the combined weight of all carried items must not exceed the frame's strength.

\begin{code}
canLift :: Robot -> Item -> Bool
canLift r item = strength (frame r) >= sum (map weight $ item : inventory r)
\end{code}

Robots also contain a register machine, which consists of a \emph{processor} and a \emph{memory}. The processor is defined purely by the number of instructions it can compute per botworld step, and the memory is simply a list of registers.

\begin{code}
newtype Processor = P { speed :: Int } deriving (Eq, Show)
type Memory = [Register]
\end{code}

In this report, the register machines use a very simple instruction set which we call the \emph{constree language}. A full implementation can be found in Appendix~\ref{app:constree}. However, when modelling concrete decision problems in botworld, we may choose to replace this simple language by something easier to use. (In particular, many robot programs will need to reason about botworld's laws. Encoding botworld into the constree language is no trivial task.)

\subsection{Items}

Botworld squares contain \emph{items} which may be manipulated by the robots. Items include \emph{robot parts} which can be used to construct robots, and \emph{shields} which can be used to protect a robot from aggressors, and various types of \emph{cargo}, a catch-all term for items that have no functional significance inside botworld but that players try to collect to increase their score.

At the end of a botworld game, a player is scored on the value of all items carried by robots in the player's \emph{home square}. We may imagine these robots being airlifted and the items in their possession being given to the player. The value of different items varies from game to game; see Section~\ref{sec:games} for details.

Robot parts are either \emph{processors}, \emph{registers}, or \emph{frames}.

\begin{code}
data Item
  = Cargo { cargoType :: Int, cargoWeight :: Int }
  | ProcessorPart Processor
  | RegisterPart Register
  | FramePart Frame
  | Shield
  deriving (Eq, Show)
\end{code}

Every item has a weight. Shields, registers and processors are light. Frames are heavy. The weight of cargo is variable.

\begin{code}
weight :: Item -> Int
weight (Cargo _ w) = w
weight Shield = 1
weight (RegisterPart _) = 1
weight (ProcessorPart _) = 1
weight (FramePart _) = 100
\end{code}

Robots can construct other robots from component parts. Specifically, a robot may be constructed from one frame, one processor, and any number of registers.\footnote{The following code introduces the helper function |singleton :: [a] -> Maybe a| which returns |Just x| when given |[x]| and Nothing otherwise, as well as the helper functions |isFrame, isProcessor, isPart :: Item -> Bool|, all of which are defined in Appendix~\ref{app:helpers}.}

\begin{code}
construct :: [Item] -> Maybe Robot
construct parts = do
  FramePart f <- singleton $ filter isFrame parts
  ProcessorPart p <- singleton $ filter isProcessor parts
  let robot = Robot f [] p [r | RegisterPart r <- parts]
  if all isPart parts then Just robot else Nothing
\end{code}

Robots may also shatter robots into their component parts. As you might imagine, each robot is deconstructed into a frame, a processor, and a handful of registers.

\begin{code}
shatter :: Robot -> [Item]
shatter r = FramePart (frame r) : ProcessorPart (processor r) : rparts where
  rparts = map (RegisterPart . forceR Nil) (memory r)
\end{code}

\subsection{Commands and actions}

Robot machines have a special \emph{output register} which is used to determine the action taken by the robot in the step. Robot machines are run at the \emph{end} of each botworld step, and are expected to leave a command in the output register. This command determines the behavior of the robot in the following step.

Available commands are:

\begin{itemize*}
  \item |Move|, for moving around the grid.
  \item |Lift|, for lifting items.
  \item |Drop|, for dropping items.
  \item |Inspect|, for reading the contents of another robot's register machine.
  \item |Destroy|, for destroying robots.
  \item |Build|, for creating new robots.
  \item |Pass|, which has the robot do nothing.
\end{itemize*}

\begin{code}
data Command
  = Move Direction
  | Lift Int
  | Drop Int
  | Inspect Int
  | Destroy Int
  | Build [Int] Memory
  | Pass
  deriving Show
\end{code}

Depending upon the state of the world, the robots may or may not actually execute their chosen command. For instance, if the robot attempts to move into a wall, the robot will fail. The actual actions that a robot may end up taking are given below. Their meanings will be made explicit momentarily (though you can guess most of them from the names).

\begin{code}
data Action
  = Created
  | Passed
  | MoveBlocked Direction
  | MovedOut Direction
  | MovedIn Direction
  | CannotFit Int
  | GrappledOver Int
  | Lifted Int
  | Dropped Item
  | InspectTargetFled Int
  | InspectBlocked Int
  | Inspected Int Robot
  | DestroyTargetFled Int
  | DestroyBlocked Int
  | Destroyed Int
  | BuildInterrupted [Int]
  | Built [Int] Robot
  | Invalid
  deriving (Eq, Show)

\end{code}

\subsection{The step function}

Botworld cells are updated given only the current state of the cell and the states of all surrounding cells. Wall cells are immutable, and thus we need only define the step function on squares.

\begin{code}
step :: Square -> [(Direction, Cell)] -> Square
\end{code}

We begin by computing what each robot would like to do. We do this by reading from (and then zeroing out) the output register of the robot's register machine.

This leaves us both with a list of robots (which have had their machine's output register zeroed out) and a corresponding list of robot outputs.

\savecolumns
\begin{code}
step sq neighbors = Square robots' items' where
  (robots, intents) = unzip $ map takeOutput $ robotsIn sq
\end{code}

Notice that we read the robot's output register at the beginning of each botworld step. (We run the robot register machines at the end of each step.) This means that robots must be initialized with their first command in the output register.

Before we can compute the actions that are actually taken by each robot, we need to compute some data that will help us identify failed actions.

\paragraph{Items may only be lifted or used to build robots if no other robot is also validly lifting or using the item.} In order to detect such conflicts, we generate a list of items which corresponds by index to the cell's item list, except with contested items missing.

\restorecolumns
\begin{code}
  itemTargets :: [Maybe Item]
  itemTargets = map contest uses where
    uses = validLifts ++ concat validBuilds
\end{code}

We determine the indices of items that robots want to lift by looking at all lift orders that the ordering robot could in fact carry out:\footnote{The following code introduces the helper function |(!!?) :: [a] -> Int -> Maybe a|, used to safely index into lists, which is defined in Appendix~\ref{app:helpers}.}

\restorecolumns
\begin{code}
    validLifts = [i | (r, Lift i) <- orders, isValidLift r i]
    isValidLift r i = maybe False (canLift r) (itemsIn sq !!? i)
    orders = [(r, cmd) | (r, Just cmd) <- zip robots intents]
\end{code}

We then determine the indices of items that robots want to use to build other robots by looking at all build orders that actually do describe a robot:

\restorecolumns
\begin{code}
    validBuilds = [is | Build is _ <- catMaybes intents, isValidBuild is]
    isValidBuild = maybe False (isJust . construct) . mapM (itemsIn sq !!?)
\end{code}

We may then determine which items are in high demand, and generate our item list with those items removed.

\restorecolumns
\begin{code}
    contest i = if i `elem` delete i uses then Nothing else itemsIn sq !!? i
\end{code}

\paragraph{Robots may only be destroyed or inspected if they do not possess adequate shields.} Every attack (|Destroy| or |Inspect| command) targeting a robot destroys one of the robot's shields. So long as the robot possesses more shields than attackers, the robot is not affected. However, if the robot is attacked by more robots than it has shields, then all of its shields are destroyed \emph{and} all of the attacks succeed (in a wild frenzy, presumably).

To implement this behavior, we generate first a list corresponding by index to the robot list which specifies the number of attacks that each robot receives in this step:

\restorecolumns
\begin{code}
  attacks :: [Int]
  attacks = map numAttacks [0..] where
    numAttacks i = length $ filter (== i) allAttacks
    allAttacks = mapMaybe (getAttack =<<) intents
    getAttack (Inspect i) = Just i
    getAttack (Destroy i) = Just i
    getAttack _ = Nothing
\end{code}

We then generate a list corresponding by index to the robot list which for each robot determines whether that robot is adequately shielded in this step\footnote{This function introduces the helper function |isShield :: Item -> Bool| defined in Appendix~\ref{app:helpers}.}:

\restorecolumns
\begin{code}
  shielded :: [Bool]
  shielded = zipWith isShielded [0..] robots where
    isShielded i r = (attacks !! i) <= length (filter isShield $ inventory r)
\end{code}

\paragraph{Any robot that exits the square in this step cannot be attacked in this step.} Moving robots evade their pursuers. The shields of moving robots are not destroyed. Note that this is not a foolproof defense: a robot cornered by walls had best have some shields handy. Nevertheless, we define a function that determines whether a robot has fled. This function makes use of the fact that movement commands into non-wall cells always succeed.

\restorecolumns
\begin{code}
  fled :: Maybe Command -> Bool
  fled (Just (Move dir)) = isJust $ join $ lookup dir neighbors
  fled _ = False
\end{code}

We may now map robot commands onto the actions that the robots actually take. We begin by noting that any robot with invalid output takes the |Invalid| action.

\restorecolumns
\begin{code}
  resolve :: Robot -> Maybe Command -> Action
  resolve robot = maybe Invalid act where
\end{code}

As we have seen, |Move| commands fail only when the robot attempts to move into a wall cell.

\restorecolumns
\begin{code}
    act (Move dir) = (if isJust cell then MovedOut else MoveBlocked) dir
      where cell = join $ lookup dir neighbors
\end{code}

|Lift| commands can fail in three different ways:

\begin{enumerate*}
  \item If the item index is out of range, the command is invalid.
  \item If the item is not an available target then multiple robots have attempted to use the same item.
  \item If the robot lacks the strength to hold the item, the lift fails.
\end{enumerate*}

Otherwise, the lift succeeds.

\restorecolumns
\begin{code}
    act (Lift i) = maybe Invalid tryLift $ itemTargets !!? i where
      tryLift = maybe (GrappledOver i) pickUp
      pickUp item = (if canLift robot item then Lifted else CannotFit) i
\end{code}

|Drop| commands always succeed so long as the robot actually possesses the item they attempt to drop.

\restorecolumns
\begin{code}
    act (Drop i) = maybe Invalid Dropped (inventory robot !!? i)
\end{code}

|Inspect| commands, like |Lift| commands, may fail in three different ways:

\begin{enumerate*}
  \item If the specified robot does not exist, the command is invalid.
  \item If the specified robot moved away, the inspection fails.
  \item If the specified robot had sufficient shields this step, the inspection is blocked.
\end{enumerate*}

Otherwise, the inspection succeeds.

\restorecolumns
\begin{code}
    act (Inspect i) = maybe Invalid tryInspect (robots !!? i) where
      tryInspect target
        | fled (intents !! i) = InspectTargetFled i
        | shielded !! i = InspectBlocked i
        | otherwise = Inspected i target
\end{code}

Destroy commands are similar to inspect commands: if the given index actually specifies a victim in the robot list, and the victim is not moving away, and the victim is not adequately shielded, then the victim is destroyed.

Robots \emph{can} destroy themselves. Programs should be careful to avoid unintentional self-destruction.

\restorecolumns
\begin{code}
    act (Destroy i) = maybe Invalid tryDestroy (robots !!? i) where
      tryDestroy _
        | fled (intents !! i) = DestroyTargetFled i
        | shielded !! i = DestroyBlocked i
        | otherwise = Destroyed i
\end{code}

Build commands must also pass three checks in order to succeed:

\begin{enumerate*}
  \item All of the specified indexes must specify actual items.
  \item All of the specified items must not be contested.
  \item The items must together specify a robot.
\end{enumerate*}

\restorecolumns
\begin{code}
    act (Build is m) = maybe Invalid tryBuild parts where
      parts = mapM (itemTargets !!?) is
      tryBuild = maybe (BuildInterrupted is) buildUsing . sequence
      buildUsing = maybe Invalid (Built is . initialize m) . construct
\end{code}

Pass commands always succeed.

\restorecolumns
\begin{code}
    act Pass = Passed
\end{code}

With the |resolve| function in hand it is trivial to compute the actions actually executed by the robots in the square:

\restorecolumns
\begin{code}
  localActions :: [Action]
  localActions = zipWith resolve robots intents
\end{code}

With this data we can determine which robots left the square and which robots were destroyed. It is convenient to know, for each robot which began in this square, whether that robot is still in this square and (if they are) whether they survived. We store that data in the following list (which corresponds by index to the original robot list):

\restorecolumns
\begin{code}
  survived :: [Maybe Bool]
  survived = zipWith check [0..] localActions where
    check _ (MovedOut _) = Nothing
    check n _ = Just $ n `notElem` [i | Destroyed i <- localActions]
\end{code}

We then compute the updated inventories of all robots who began in this square. (The inventories of moving robots are not changed, so we need not update the inventory of robots entering this square.)

Robot inventories are updated whenever the robot executes a |Lift| action, executes a |Drop| action, or experiences an attack (in which case shields may be destroyed.) Notice that shields are destroyed in order according to the ordering of the targeted robot's inventory.\footnote{The following code introduces the helper function |dropN :: Int -> (a -> Bool) -> [a] -> [a]|, which drops the first |n| items matching the given predicate. It is defined in Appendix~\ref{app:helpers}.}

\restorecolumns
\begin{code}
  updateInventory :: Int -> Action -> Robot -> Robot
  updateInventory i a r = case a of
    MovedOut _ -> r
    Lifted n -> r{inventory=(itemsIn sq !! n) : defended}
    Dropped item -> r{inventory=delete item defended}
    _ -> r{inventory=defended}
    where defended = dropN (attacks !! i) isShield $ inventory r
\end{code}

We use this function to update the inventories of all robots that were originally in this square. Notice that the inventories of destroyed robots are updated as well: destroyed robots get to perform their actions before they are destroyed.

\restorecolumns
\begin{code}
  veterans :: [Robot]
  veterans = zipWith3 updateInventory [0..] localActions robots where
\end{code}

Next, we identify which robots enter this square from other squares. We compute this by looking at the intents of the robots in neighboring squares. Remember that move commands always succeed if the robot is moving into a non-wall square. Thus, all robots in neighboring squares which intend to move into this square will successfully move into this square.

\restorecolumns
\begin{code}
  incomingFrom :: (Direction, Cell) -> [(Robot, Direction)]
  incomingFrom (dir, neighbor) = mapMaybe movingThisWay cmds where
    cmds = maybe [] (map takeOutput . robotsIn) neighbor
    movingThisWay (robot, Just (Move dir'))
      | dir == opposite dir' = Just (robot, dir)
    movingThisWay _ = Nothing
\end{code}

We compute both a list of entering robots and a corresponding list of the directions which those robots entered from.

\restorecolumns
\begin{code}
  (travelers, origins) = unzip $ concatMap incomingFrom neighbors
\end{code}

We also determine the list of robots that have been created in this timestep:

\restorecolumns
\begin{code}
  children = [r | Built _ r <- localActions]
\end{code}

All remaining robots will have their register machines run before the next step. Before they may be run, however, their input registers must be updated. Each robot recieves five inputs:

\begin{enumerate*}
\item The host robot's index in the following list
\item The list of all robots in the square, including robots that exited, entered, were destroyed, and were created.
\item A list of actions for each robot, corresponding to the list above.
\item The updated item list>
\item Some private input.
\end{enumerate*}

We have already largely computed the list of all robots. It is worth noting here that when this robot list is converted into machine input, some information will be lost: processors and memories are not visible to other robots (except via |Inspect| commands). This data-hiding is implemented by the constree encoding code; see Appendix~\ref{app:encoding} for details.

\restorecolumns
\begin{code}
  allRobots :: [Robot]
  allRobots = veterans ++ travelers ++ children
\end{code}

Computing the list of all actions is similarly simple. As with the robot list, some of this data will be lost when it is converted into machine input. Specifically, robots cannot distinguish between |Passed| and |Invalid| actions. Also, the results of an |Inspect| command are visible only to the inspecting robot. Again, this data-hiding is implemented by the constree encoding code; see Appendix~\ref{app:encoding} for details.

\restorecolumns
\begin{code}
  allActions :: [Action]
  allActions = localActions ++ travelerActions ++ childActions where
    travelerActions = map MovedIn origins
    childActions = replicate (length children) Created
\end{code}

We now compute the item list. It is given in three groups.

The items that were unaffected:

\restorecolumns
\begin{code}
  unaffected :: [Item]
  unaffected = removeIndices (lifts ++ concat builds) (itemsIn sq) where
    lifts = [i | Lifted i <- localActions]
    builds = [is | Built is _ <- localActions]
\end{code}

The items that were willingly dropped by robots:

\restorecolumns
\begin{code}
  dropped :: [Item]
  dropped = [item | Dropped item <- localActions]
\end{code}

And the fallen items from destroyed robots, which is given in groups of part/inventory pairs:

\restorecolumns
\begin{code}
  fallen :: [([Item], [Item])]
  fallen = [itemsOf r | (r, Just False) <- zip veterans survived] where
    itemsOf r = (shatter r, filter (not . isShield) (inventory r))
\end{code}

The item list retains some structure when it is encoded as robot input, which helps robots determine what happened to which items.

The final piece of robot input is private. If the robot executed a successful |Inspect| command then the private input includes information about the inspected robot's machine.

Also, the private input differentiates between |Invalid| and |Passed| actions in a private fashion, so that each individual machine can know whether \emph{it itself} gave an invalid command in the previous step. (All other robots cannot distinguish between |Invalid| and |Passed| actions.)

\restorecolumns
\begin{code}
  privateInput :: Action -> Constree
  privateInput Invalid = encode (1 :: Int)
  privateInput (Inspected _ r) = encode
    (processor r, length $ memory r, memory r)
  privateInput _ = encode (0 :: Int)
\end{code}

With these inputs in hand, we can run any given robot by updating their input register appropriately and then running the robot's register machine:

\restorecolumns
\begin{code}
  run :: Int -> Action -> Robot -> Robot
  run index action robot = runMachine $ setInput robot input where
    input = (index, allRobots, allActions, items, privateInput action)
    items = (unaffected, dropped, fallen)
\end{code}

The register machines are run as described in the following function. It makes use of the constree register machine; refer to Appendix~\ref{app:constree} for details.

\restorecolumns
\begin{code}
  runMachine :: Robot -> Robot
  runMachine robot = case runFor (speed $ processor robot) (memory robot) of
    Right memory' -> robot{memory=memory'}
    Left _ -> robot{memory=map (forceR Nil) (memory robot)}
\end{code}

We only run robots that both stayed in the square and were not destroyed. We figure out which robots stayed and survived according to their index in the list of all robots.

We can look this data up in the |survived| list created previously, remembering that all indices which don't show up in the list denote robots that either entered or were created (and that all such robots are present).

\restorecolumns
\begin{code}
  present :: Int -> Bool
  present = maybe True (fromMaybe False) . (survived !!?)
\end{code}

We then construct the new robot list by running all present robots.

\restorecolumns
\begin{code}
  robots' :: [Robot]
  robots' = [run i a r | (i, a, r) <- triples, present i] where
    triples = zip3 [0..] allActions allRobots
\end{code}

It remains only to specify the updated item list. This is the same as the updated item list that was passed to the robots as input, with the additional structure removed.

\restorecolumns
\begin{code}
  items' :: [Item]
  items' = unaffected ++ dropped ++ concat [xs ++ ys | (xs, ys) <- fallen]
\end{code}

This fully specifies the step function for botworld cells. To reiterate:

\begin{enumerate*}
  \item Robot machine output registers are read to determine robot intents.
  \item Robot actions are computed from robot intents.
  \item Robot inventories are updated.
  \item Incoming robots are computed.
  \item Unmoved, dropped, and fallen items are computed.
  \item Destroyed robots are removed, constructed robots are added.
  \item Machine input registers are set according to the updated state.
  \item Robot register machines are executed (and are expected to leave a command in the output register for the next step).
  \item The updated item list is constructed.
\end{enumerate*}

\subsection{Games} \label{sec:games}

Botworld games can vary widely. A simple game that botworld lends itself to easily is a knapsack game, in which players attempt to maximize the value of the items collected by robots which they control. (This is an NP-hard problem in general.)

Remember that \emph{robots are not players}: a player may only be able to specify the initial program for a single robot, but players may well attempt to acquire whole fleets of robots with code distributed throughout.

As such, botworld games are not scored according to the possessions of any particular robot. Rather, each player is assigned a \emph{home square}, and the score of a player is computed according to the items possessed by all robots in the player's home square at the end of the game. (The robots are airlifted out and their items are extracted for delivery to the player.) Thus, a game configuration also needs to assign specific values to the various items.

Formally, we define a game configuration as follows:

\begin{code}
data GameConfig = GameConfig
  { players :: [(Position, String)]
  , valuer :: Item -> Int
  }
\end{code}

With a game configuration in hand, we can compute how many points a single robot has achieved:

\begin{code}
points :: Robot -> Reader GameConfig Int
points r = (\value -> sum (map value $ inventory r)) <$> asks valuer
\end{code}

Then we can compute the total score in any particular square:

\begin{code}
score :: BotWorld -> Position -> Reader GameConfig Int
score g = maybe (return 0) (fmap sum . mapM points . robotsIn) . at g
\end{code}

We do not provide any example games in this report. Some example games are forthcoming.

\section{Concluding notes}

Botworld allows us to study self-modifying agents in a world where the agents are embedded \emph{within} the environment. Botworld admits a wide variety of games, including games with Newcomb-like problems and games with NP-hard tasks.

Botworld provides a very concrete environment in which to envision agents. This has proved quite useful when considering obstacles of self-reference: the concrete model often makes it easier to envision difficulties and probe edge cases.

Furthermore, botworld allows us to constructively illustrate issues that we come across by providing a concrete game in which the issue presents itself. This can often help make the abstract problems of self-reference easier to visualize.

Forthcoming papers will illustrate some of the discoveries that we've made using botworld.

\newpage
\begin{appendices}

\section{Grid Manipulation} \label{app:grid}

This report uses a quick-and-dirty |Grid| implementation wherein a grid is represented by a flat list of cells. This grid implementation specifies a wraparound grid (pacman style), which means that every position is valid.

Botworld is not tied to this particular grid implementation: non-wrapping grids, infinite grids, or even non-euclidean grids could house botworld games. We require only that squares agree on who their neighbors are: if square A is north of square B, then square B must be south of square A.

\begin{code}
type Dimensions = (Int, Int)
type Position = (Int, Int)

data Grid a = Grid
  { dimensions :: Dimensions
  , cells :: [a]
  } deriving Eq

locate :: Dimensions -> Position -> Int
locate (x, y) (i, j) = (j `mod` y) * x + (i `mod` x)

indices :: Grid a -> [Position]
indices (Grid (x, y) _) = [(i, j) | j <- [0..pred y], i <- [0..pred x]]

at :: Grid a -> Position -> a
at (Grid dim xs) p = xs !! locate dim p

change :: (a -> a) -> Position -> Grid a -> Grid a
change f p (Grid dim as) = Grid dim $ alter (locate dim p) f as

generate :: Dimensions -> (Position -> a) -> Grid a
generate dim gen = let g = Grid dim (map gen $ indices g) in g
\end{code}

\subsection{Directions}

Each square has eight neighbors (or up to eight neighbors, in finite non-wrapping grids). Each neighbor lies in one of eight directions, termed according to the cardinal directions. We now formally name those directions and specify how directions alter grid positions.

\begin{code}
data Direction = N | NE | E | SE | S | SW | W | NW
  deriving (Eq, Ord, Enum, Show)

opposite :: Direction -> Direction
opposite d = iterate (if d < S then succ else pred) d !! 4

towards :: Direction -> Position -> Position
towards d (x, y) = (x + dx, y + dy) where
  dx = [0, 1, 1, 1, 0, -1, -1, -1] !! fromEnum d
  dy = [-1, -1, 0, 1, 1, 1, 0, -1] !! fromEnum d
\end{code}

\subsection{Botworld Grids}

Finally, we define a function that updates an entire botworld grid by one step:

\begin{code}
update :: BotWorld -> BotWorld
update g = g{cells=map doStep $ indices g} where
  doStep pos = flip step (fellows pos) <$> at g pos
  fellows pos = map (walk pos) [N ..]
  walk p d = (d, at g $ towards d p)
\end{code}

\section{Constree Language} \label{app:constree}

Robots contain register machines, which run a little Turing complete language which we call the \emph{constree language}. There is only one data structure in constree, which is (unsurprisingly) the cons tree:

\begin{code}
data Constree = Cons Constree Constree | Nil deriving (Eq, Show)
\end{code}

Constrees are stored in registers, each of which has a memory limit.

\begin{code}
data Register = R { limit :: Int, contents :: Constree } deriving (Eq, Show)
\end{code}

Each tree has a size determined by the number of conses in the tree. It may be more efficient for the size of the tree to be encoded directly into the |Cons|, but we are optimizing for clarity over speed, so we simply compute the size whenever it is needed.

A tree can only be placed in a register if the size of the tree does not exceed the size limit on the register.

\begin{code}
size :: Constree -> Int
size Nil = 0
size (Cons t1 t2) = succ $ size t1 + size t2
\end{code}

Constrees are trimmed from the right. This is important only when you try to shove a constree into a register where the constree does not fit.

\begin{code}
trim :: Int -> Constree -> Constree
trim _ Nil = Nil
trim x t@(Cons front back)
  | size t <= x = t
  | size front < x = Cons front $ trim (x - succ (size front)) back
  | otherwise = Nil
\end{code}

There are two ways to place a tree into a register: you can force the tree into the register (in which case the register gets set to nil if the tree does not fit), or you can fit the tree into the register (in which case the tree gets trimmed if it does not fit).

\begin{code}
forceR :: Constree -> Register -> Register
forceR t r = if size t <= limit r then r{contents=t} else r{contents=Nil}

fitR :: Encodable i => i -> Register -> Register
fitR i r = forceR (trim (limit r) (encode i)) r
\end{code}

The constree language has only four instructions:

\begin{enumerate*}
  \item One to make the contents of a register nil.
  \item One to cons two registers together into a third register.
  \item One to deconstruct a register into two other registers.
  \item One to conditionally copy one register into another register, but only if the test register is nil.
\end{enumerate*}

\begin{code}
data Instruction
  = Nilify Int
  | Construct Int Int Int
  | Deconstruct Int Int Int
  | CopyIfNil Int Int Int
  deriving (Eq, Show)
\end{code}

A machine is simply a list of such registers. The first register is the program register, the second is the input register, the third is the output register, and the rest are workspace registers.

\begin{code}
\end{code}

The following code implements the above construction set on a constree register machine:

\begin{code}
data Error
  = BadInstruction Constree
  | NoSuchRegister Int
  | DeconstructNil Int
  | OutOfMemory Int
  | InvalidOutput
  deriving (Eq, Show)

getTree :: Int -> Memory -> Either Error Constree
getTree i m = maybe (Left $ NoSuchRegister i) (Right . contents) (m !!? i)

setTree :: Constree -> Int -> Memory -> Either Error Memory
setTree t i m = maybe (Left $ NoSuchRegister i) go (m !!? i) where
  go r = if size t > limit r then Left $ OutOfMemory i else
    Right $ alter i (const r{contents=t}) m

execute :: Instruction -> Memory -> Either Error Memory
execute instruction m = case instruction of
  Nilify tgt -> setTree Nil tgt m
  Construct fnt bck tgt -> do
    front <- getTree fnt m
    back <- getTree bck m
    setTree (Cons front back) tgt m
  Deconstruct src fnt bck -> case getTree src m of
    Left err -> Left err
    Right Nil -> Left $ DeconstructNil src
    Right (Cons front back) -> setTree front fnt m >>= setTree back bck
  CopyIfNil tst src tgt -> case getTree tst m of
    Left err -> Left err
    Right Nil -> getTree src m >>= (\t -> setTree t tgt m)
    Right _ -> Right m

runFor :: Int -> Memory -> Either Error Memory
runFor 0 m = Right m
runFor _ [] = Right []
runFor _ (r:rs) | contents r == Nil = Right $ r:rs
runFor n (r:rs) = tick >>= runFor (pred n) where
  tick = maybe badInstruction doInstruction (decode $ contents r)
  badInstruction = Left $ BadInstruction $ contents r
  doInstruction (i, is) = execute i (r{contents=is} : rs)
\end{code}

\subsection{Robot/machine interactions}

Aside from executing robot machines, there are three ways that botworld changes a robot's register machines:

\paragraph{A robot may have its machine written.} This happens whenever the machine is constructed.

\begin{code}
initialize :: Memory -> Robot -> Robot
initialize m robot = robot{memory=fitted} where
  fitted = zipWith (forceR . contents) m (memory robot) ++ padding
  padding = map (forceR Nil) (drop (length m) (memory robot))
\end{code}

\paragraph{A robot may have its output register read.} Whenever the output register is read, it is set to |Nil| thereafter.

Programs may use this fact to implement a wait-loop that waits until output is read before proceeding: after output is read, input will be updated before the next instruction is executed, so machines waiting for a |Nil| output can be confident that when the output register becomes |Nil| there will be new input in the input register.

A robot's output register is read at the beginning of eac htick.

\begin{code}
takeOutput :: Decodable o => Robot -> (Robot, Maybe o)
takeOutput robot = maybe (robot, Nothing) go (m !!? 2) where
  go o = (robot{memory=alter 2 (forceR Nil) m}, decode $ contents o)
  m = memory robot
\end{code}

\paragraph{A robot may have its machine input register set.} This happens just before the machine is executed in every botworld step.

\begin{code}
setInput :: Encodable i => Robot -> i -> Robot
setInput robot i = robot{memory=set1} where
  set1 = alter 1 (fitR i) (memory robot)
\end{code}

\subsection{Encoding and Decoding} \label{app:encoding}

The following section specifies how haskell data structures are encoded into constrees and decoded from constrees. It is largely mechanical, with a few exceptions noted inline.

\begin{code}
class Encodable t where
  encode :: t -> Constree

class Decodable t where
  decode :: Constree -> Maybe t

instance Encodable Constree where
  encode = id

instance Decodable Constree where
  decode = Just

instance Encodable t => Encodable (Maybe t) where
  encode = maybe Nil (Cons Nil . encode)

instance Decodable t => Decodable (Maybe t) where
  decode Nil = Just Nothing
  decode (Cons Nil x) = Just <$> decode x
  decode _ = Nothing

instance Encodable t => Encodable [t] where
  encode = foldr (Cons . encode) Nil

instance Decodable t => Decodable [t] where
  decode Nil = Just []
  decode (Cons t1 t2) = (:) <$> decode t1 <*> decode t2
\end{code}

Lisp programmers may consider it more parsimonious to encode tuples like lists, with a Nil at the end. There is some sleight of hand going on here, however: machine inputs are encoded tuples, and the inputs may sometimes need to be trimmed to fit into a register. If a robot has executed an |Inpsect| command, then the entire contents of the inspected robot will be dumped into the inspector's input register. In many cases, the entire memory of the target robot is not likely to fit into the input register of the inspector. In such cases, we would like as many full encoded registers to be fit into the input as possible.

Because cons trees are trimmed from the right, we get this behavior for free if we forgo the terminal |Nil| when encoding tuple objects. With this implementation, the memory of the inspected robot (which is a list) will be the rightmost item in the cons tree, and if it does not fit, the registers will be lopped off one at a time. (By contrast, if we Nil-terminated tuple encodings and the machine did not fit, then the entire machine would be trimmed.)

\begin{code}
instance (Encodable a, Encodable b) => Encodable (a, b) where
  encode (a, b) = Cons (encode a) (encode b)

instance (Decodable a, Decodable b) => Decodable (a, b) where
  decode (Cons a b) = (,) <$> decode a <*> decode b
  decode Nil = Nothing

instance (Encodable a, Encodable b, Encodable c) => Encodable (a, b, c) where
  encode (a, b, c) = encode (a, (b, c))

instance (Decodable a, Decodable b, Decodable c) => Decodable (a, b, c) where
  decode = fmap flatten . decode where flatten (a, (b, c)) = (a, b, c)

instance (Encodable a, Encodable b, Encodable c, Encodable d, Encodable e) =>
  Encodable (a, b, c, d, e) where
  encode (a, b, c, d, e) = encode (a, (b, (c, (d, e))))

instance Encodable Bool where
  encode False = Nil
  encode True = Cons Nil Nil

instance Decodable Bool where
  decode Nil = Just False
  decode (Cons Nil Nil) = Just True
  decode _ = Nothing

instance Encodable Int where
  encode n
    | n < 0 = Cons (Cons Nil (Cons Nil Nil)) (encode $ negate n)
    | otherwise = encode $ bits n
    where
      bits 0 = []
      bits x = let (q, r) = quotRem x 2 in (r == 1) : bits q

instance Decodable Int where
  decode (Cons (Cons Nil (Cons Nil Nil)) n) = fmap negate $ decode n
  decode t = unbits <$> decode t where
    unbits [] = 0
    unbits (x:xs) = (if x then 1 else 0) + 2 * unbits xs

instance Encodable Instruction where
  encode instruction = case instruction of
    Nilify tgt               -> encode (0 :: Int, tgt)
    Construct fnt bck tgt    -> encode (1 :: Int, (fnt, bck, tgt))
    Deconstruct src fnt bck  -> encode (2 :: Int, (src, fnt, bck))
    CopyIfNil tst src tgt    -> encode (3 :: Int, (tst, src, tgt))

instance Decodable Instruction where
  decode t = case decode t :: Maybe (Int, Constree) of
    Just (0, arg)   -> Nilify <$> decode arg
    Just (1, args)  -> uncurry3 Construct <$> decode args
    Just (2, args)  -> uncurry3 Deconstruct <$> decode args
    Just (3, args)  -> uncurry3 CopyIfNil <$> decode args
    _               -> Nothing
    where uncurry3 f (a, b, c) = f a b c

instance Encodable Register where
  encode r = encode (limit r, contents r)

instance Decodable Register where
  decode = fmap (uncurry R) . decode

instance Encodable Color where
  encode = encode . fromEnum

instance Encodable Frame where
  encode (F c s) = encode (c, s)

instance Encodable Processor where
  encode (P s) = encode s

instance Encodable Item where
  encode (Cargo t w)        = encode (0 :: Int, t, w)
  encode (RegisterPart r)   = encode (1 :: Int, r)
  encode (ProcessorPart p)  = encode (2 :: Int, p)
  encode (FramePart f)      = encode (3 :: Int, f)
  encode Shield             = encode (4 :: Int, Nil)

instance Encodable Direction where
  encode = encode . fromEnum

instance Decodable Direction where
  decode t = ([N ..] !!?) =<< decode t
\end{code}

Note that only the robot's frame and inventory are encoded into contree. The processor and memory are omitted, as these are not visible in the machine inputs.

\begin{code}
instance Encodable Robot where
  encode (Robot f i _ _) = encode (f, i)

instance Encodable Command where
  encode (Move d)      = encode (0 :: Int, head $ elemIndices d [N ..])
  encode (Lift i)      = encode (1 :: Int, i)
  encode (Drop i)      = encode (2 :: Int, i)
  encode (Inspect i)   = encode (3 :: Int, i)
  encode (Destroy i)   = encode (4 :: Int, i)
  encode (Build is m)  = encode (5 :: Int, is, m)
  encode Pass          = encode (6 :: Int, Nil)
\end{code}

\begin{code}
instance Decodable Command where
  decode t = case decode t :: Maybe (Int, Constree) of
    Just (0, d)    -> Move <$> (([N ..] !!?) =<< decode d)
    Just (1, i)    -> Lift <$> decode i
    Just (2, i)    -> Drop <$> decode i
    Just (3, i)    -> Inspect <$> decode i
    Just (4, i)    -> Destroy <$> decode i
    Just (5, x)    -> uncurry Build <$> decode x
    Just (6, Nil)  -> Just Pass
    _              -> Nothing
\end{code}

Note that |Passed| actions and |Invalid| actions are encoded identically: robots cannot distinguish these actions. Note also that |Inspected| actions do not encode the result of the inspection.

\begin{code}
instance Encodable Action where
  encode a = case a of
    Passed               -> encode (0  :: Int, Nil)
    Invalid              -> encode (0  :: Int, Nil)
    Created              -> encode (1  :: Int, Nil)
    MoveBlocked d        -> encode (4  :: Int, direction d)
    MovedOut d           -> encode (2  :: Int, direction d)
    MovedIn d            -> encode (3  :: Int, direction d)
    CannotFit i          -> encode (6  :: Int, i)
    GrappledOver i       -> encode (7  :: Int, i)
    Lifted i             -> encode (5  :: Int, i)
    Dropped _            -> encode (8  :: Int, Nil)
    InspectTargetFled i  -> encode (9  :: Int, i)
    InspectBlocked i     -> encode (10 :: Int, i)
    Inspected i _        -> encode (11 :: Int, i)
    DestroyTargetFled i  -> encode (12 :: Int, i)
    DestroyBlocked i     -> encode (13 :: Int, i)
    Destroyed i          -> encode (14 :: Int, i)
    Built is _           -> encode (15 :: Int, is)
    BuildInterrupted is  -> encode (16 :: Int, is)
    where direction d = head $ elemIndices d [N ..]
\end{code}

\section{Helper Functions} \label{app:helpers}

This section contains simple helper functions used to implement the botworld step function. Three are used to distinguish different types of items, and one is used to distinguish a specific type of action:

\begin{code}
isPart :: Item -> Bool
isPart (RegisterPart _) = True
isPart item = isProcessor item || isFrame item

isProcessor :: Item -> Bool
isProcessor (ProcessorPart _) = True
isProcessor _ = False

isFrame :: Item -> Bool
isFrame (FramePart _) = True
isFrame _ = False

isShield :: Item -> Bool
isShield Shield = True
isShield _ = False
\end{code}

The other four are generic functions that assist with list manipulation: one to extract a single item from a list (or fail if the list has many items):

\begin{code}
singleton :: [a] -> Maybe a
singleton [x] = Just x
singleton _ = Nothing
\end{code}

one to safely access items in a list at a given index:

\begin{code}
(!!?) :: [a] -> Int -> Maybe a
[] !!? _ = Nothing
(x:_) !!? 0 = Just x
(_:xs) !!? n = xs !!? pred n
\end{code}

one to safely alter a specific item in a list:

\begin{code}
alter :: Int -> (a -> a) -> [a] -> [a]
alter i f xs = maybe xs go (xs !!? i) where
  go x = take i xs ++ (f x : drop (succ i) xs)
\end{code}

one to remove a specific set of indices from a list:

\begin{code}
removeIndices :: [Int] -> [a] -> [a]
removeIndices = flip $ foldr remove where
  remove :: Int -> [a] -> [a]
  remove i xs = take i xs ++ drop (succ i) xs
\end{code}

and one to selectively drop the first |n| items that match the given predicate.

\begin{code}
dropN :: Int -> (a -> Bool) -> [a] -> [a]
dropN 0 _ xs = xs
dropN n p (x:xs) = if p x then dropN (pred n) p xs else x : dropN n p xs
dropN _ _ [] = []
\end{code}


\section{Visualization} \label{app:visualization}

The remaining code implements a visualizer for botworld grids. This allows you to print out botworld grids and botworld scoreboards (assuming that you have access to a botworld game configuration).

In botworld grid visualizations, colors are given a three-letter code:

\begin{code}
instance Show Color where
  show Red = "RED"
  show Orange = "RNG"
  show Yellow = "YLO"
  show Green = "GRN"
  show Blue = "BLU"
  show Violet = "VLT"
  show Black = "BLK"
  show White = "WYT"
\end{code}

Each cell is shown using three lines: the first for items, the second for item weights, the third for robots (by color). At most two things are shown per row. (This is by no means a perfect visualization, but it works well for simple games.)

\savecolumns
\begin{code}
visualize :: BotWorld -> Reader GameConfig String
visualize g = do
  rowStrs <- mapM showRow rows :: Reader GameConfig [String]
  return $ concat rowStrs ++ line
  where
    unpaddedRows = chunksOf r (cells g) where (r, _) = dimensions g
    pad row = row ++ replicate (maxlen - length row) Nothing
    rows = map pad unpaddedRows
    maxlen = maximum (map length unpaddedRows)

    line = concat (replicate maxlen "+---------") ++ "+\n"
\end{code}

Items are crudely shown as follows:

\restorecolumns
\begin{code}
    showValue :: Item -> Reader GameConfig String
    showValue b = do
      value <- asks valuer
      return $ case b of
        FramePart (F Red _)     -> "[R]"
        FramePart (F Orange _)  -> "[O]"
        FramePart (F Yellow _)  -> "[Y]"
        FramePart (F Green _)   -> "[G]"
        FramePart (F Blue _)    -> "[B]"
        FramePart (F Violet _)  -> "[V]"
        FramePart (F Black _)   -> "[K]"
        FramePart (F White _)   -> "[W]"
        ProcessorPart _         -> "[#]"
        RegisterPart _          -> "[|]"
        Shield                  -> "\\X/"
        x -> printf "$%d" (value x)

    showWeight :: Item -> String
    showWeight item
      | weight item > 99 = "99+"
      | otherwise = printf "%dg" $ weight item

    showRow :: [Cell] -> Reader GameConfig String
    showRow xs = do
      v <- showCells cellValue xs
      w <- showCells cellWeight xs
      r <- showCells (return <$> cellRobots) xs
      return $ line ++ v ++ w ++ r

    showCells strify xs = do
      strs <- mapM (maybe (return "/////////") strify) xs
      return $ "|" ++ intercalate "|" strs ++ "|\n"

    cellValue sq = do
      value <- asks valuer
      case sortBy (flip $ comparing value) (itemsIn sq) of
        [] -> return "         "
        [b] -> printf "   %3s   " <$> showValue b
        [b, c] -> printf " %3s %3s " <$> showValue b <*> showValue c
        (b:c:_) -> printf " %3s %3s\x2026" <$> showValue b <*> showValue c

    cellWeight sq = do
      value <- asks valuer
      return $ case sortBy (flip $ comparing value) (itemsIn sq) of
        [] -> "         "
        [b] -> printf "   %3s   " (showWeight b)
        [b, c] -> printf " %3s %3s " (showWeight b) (showWeight c)
        (b:c:_) -> printf " %3s %3s\x2026" (showWeight b) (showWeight c)

    cellRobots sq = case sortBy (comparing $ color . frame) (robotsIn sq) of
      [] -> "         "
      [f] -> printf "   %s   " (clr f)
      [f, s] -> printf " %s %s " (clr f) (clr s)
      (f:s:_) -> printf " %s %s\x2026" (clr f) (clr s)
      where clr = show . color . frame
\end{code}

Finally, the scoreboard function takes a game configuration and prints out a scoreboard detailing the scores of each player (broken down according to the robots in the player's home square at the end of the game).

\begin{code}
scoreboard :: BotWorld -> Reader GameConfig String
scoreboard g = do
  scores <- mapM scoreCell =<< sortedPositions
  return $ unlines $ concat scores
  where
    sortedPositions = do
      ps <- map fst <$> asks players
      scores <- mapM (score g) ps
      let comparer = flip $ comparing snd
      return $ map fst $ sortBy comparer $ zip ps scores

    scoreCell p = do
      header <- playerLine p
      let divider = replicate (length header) '-'
      breakdown <- case maybe [] robotsIn $ at g p of
        [] -> return ["  No robots in square."]
        rs -> mapM robotScore rs
      return $ header : divider : breakdown

    robotScore r = do
      pts <- points r
      let name = printf "  %s robot" (show $ color $ frame r) :: String
      return $  name ++ ": $" ++ printf "%d" pts

    playerLine p = do
      total <- score g p
      name <- lookup p <$> asks players
      let moniker = fromMaybe (printf "Player at %s" (show p)) name
      return $ printf "%s $%d" moniker total
\end{code}

\end{appendices}

\end{document}
