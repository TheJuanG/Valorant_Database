--1 Average game length for each agent
SELECT a.Agent_ID, AVG(m.gameLength) AS avg_game_length
FROM Agents a
JOIN Player p ON a.Agent_ID = p.Agent_ID
JOIN MatchTeam mt ON p.Team_ID = mt.Team_ID
JOIN Matches m ON mt.Match_ID = m.Match_ID
GROUP BY a.Agent_ID
ORDER BY avg_game_length DESC;

--2 Top 3 players with the highest kill count and their favorite weapon
WITH PlayerKills AS (
    SELECT p.Player_ID, COUNT(*) AS total_kills
    FROM Player p
    JOIN Killer k ON p.Player_ID = k.Killer_ID
    GROUP BY p.Player_ID
)
SELECT TOP 3 PlayerKills.Player_ID, Player.Agent_ID, Player.Team_ID, PlayerKills.total_kills, Weapons.Type AS FavoriteWeaponType
FROM PlayerKills
JOIN (
    SELECT TOP 3 Killer_ID, Weapon_ID
    FROM Killer
    GROUP BY Killer_ID, Weapon_ID
    ORDER BY COUNT(*) DESC
) AS TopPlayerWeapon ON PlayerKills.Player_ID = TopPlayerWeapon.Killer_ID
JOIN Weapons ON TopPlayerWeapon.Weapon_ID = Weapons.Weapon_ID
JOIN Player ON PlayerKills.Player_ID = Player.Player_ID
ORDER BY PlayerKills.total_kills DESC;

--3 Retrieve the agents and the number of players using each agent
SELECT a.Agent_ID, COUNT(p.Player_ID) AS PlayerCount
FROM Agents a
LEFT JOIN Player p ON a.Agent_ID = p.Agent_ID
GROUP BY a.Agent_ID
ORDER BY PlayerCount DESC;

--4 Listing players and their total kills with the sidearm weapon type
SELECT p.Player_ID, p.Agent_ID, p.Team_ID, COUNT(k.Kill_ID) AS TotalKills
FROM Player p
JOIN Killer k ON p.Player_ID = k.Killer_ID
JOIN Weapons w ON k.Weapon_ID = w.Weapon_ID
WHERE w.Type = 'Sidearm'
GROUP BY p.Player_ID, p.Agent_ID, p.Team_ID
ORDER BY TotalKills DESC;

--5 Round number where there have been more than 350 kills across all matches
SELECT k.roundNum,
    COUNT(k.Kill_ID) AS total_kills
FROM Killer k
GROUP BY k.roundNum
HAVING COUNT(k.Kill_ID) > 350;

--6 Total number of kills for each weapon type
SELECT w.Type,
    COUNT(k.Kill_ID) AS total_kills
FROM Weapons w
JOIN Killer k ON w.Weapon_ID = k.Weapon_ID
GROUP BY w.Type
ORDER BY total_kills DESC;

--7 Player Win-rate Analysis
WITH
    PlayerWins
    AS
    (
        SELECT
            p.Player_ID,
            COUNT(*) AS TotalMatches,
            SUM(CASE WHEN mt.side = m.winningTeam THEN 1 ELSE 0 END) AS Wins
        FROM
            Player p
            INNER JOIN
            MatchTeam mt ON p.Team_ID = mt.Team_ID
            INNER JOIN
            Matches m ON mt.Match_ID = m.Match_ID
        GROUP BY
        p.Player_ID
    )

SELECT
    pw.Player_ID,
    pw.TotalMatches,
    pw.Wins,
    CAST(pw.Wins * 100.0 / NULLIF(pw.TotalMatches, 0) AS DECIMAL(5, 2)) AS WinRate
FROM
    PlayerWins pw
ORDER BY 
    WinRate DESC;

--8 Team Win-rate Analysis
SELECT
    mt.Team_ID,
    COUNT(*) AS TotalMatches,
    SUM(CASE WHEN mt.side = m.winningTeam THEN 1 ELSE 0 END) AS Wins,
    CONVERT(DECIMAL(5, 2), (SUM(CASE WHEN mt.side = m.winningTeam THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0))) AS WinRate
FROM
    MatchTeam mt
    INNER JOIN
    Matches m ON mt.Match_ID = m.Match_ID
GROUP BY
    mt.Team_ID
ORDER BY
    WinRate DESC;

--9 Best Team Win-rate per Map
WITH
    TeamWinRates
    AS
    (
        SELECT
            mt.Team_ID,
            m.mapName,
            COUNT(*) AS TotalMatches,
            SUM(CASE WHEN mt.side = m.winningTeam THEN 1 ELSE 0 END) AS Wins,
            CONVERT(DECIMAL(5, 2), (SUM(CASE WHEN mt.side = m.winningTeam THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0))) AS WinRate
        FROM
            MatchTeam mt
            INNER JOIN
            Matches m ON mt.Match_ID = m.Match_ID
        GROUP BY
        mt.Team_ID, m.mapName
    )
SELECT
    twr.mapName,
    MAX(twr.Team_ID) AS BestTeamID,
    MAX(twr.WinRate) AS MaxWinRate
FROM
    TeamWinRates twr
GROUP BY
    twr.mapName;

--10 Weapon Kill-to-Cost Ratio
WITH
    KillStats
    AS
    (
        SELECT
            k.Weapon_ID,
            SUM(k.roundNum) AS TotalKills,
            w.Cost AS Cost
        FROM
            Killer k
            JOIN Weapons w ON k.Weapon_ID = w.Weapon_ID
        GROUP BY
    k.Weapon_ID, w.Cost
    )

SELECT
    ks.Weapon_ID,
    SUM(ks.TotalKills) AS TotalKills,
    ks.Cost,
    SUM(ks.TotalKills) * 1.0 / ks.Cost AS KillsToCostRatio
FROM
    KillStats ks
GROUP BY
  ks.Weapon_ID, ks.Cost
ORDER BY
  KillsToCostRatio DESC;

--11 Top Player Kills per Team
WITH
    TeamPlayerKills
    AS
    (
        SELECT
            p.Player_ID,
            mt.Team_ID,
            COUNT(k.Kill_ID) AS TotalKills
        FROM
            Player p
            INNER JOIN
            MatchTeam mt ON p.Team_ID = mt.Team_ID
            INNER JOIN
            Killer k ON p.Player_ID = k.Killer_ID
        GROUP BY
        p.Player_ID, mt.Team_ID
    )

SELECT
    tpk.Player_ID,
    tpk.Team_ID,
    tpk.TotalKills
FROM
    TeamPlayerKills tpk
WHERE
    tpk.TotalKills = (
        SELECT TOP 1
    MAX(tpk2.TotalKills)
FROM
    TeamPlayerKills tpk2
WHERE
            tpk2.Team_ID = tpk.Team_ID
ORDER BY
            MAX(tpk2.TotalKills) DESC
    );

--12 Average Kill Efficiency Analysis (UDF)
GO
CREATE FUNCTION dbo.CalculateKillEfficiency(@TotalCost INT, @RoundNum INT)
RETURNS DECIMAL(5, 2)
AS
BEGIN
    DECLARE @Efficiency DECIMAL(5, 2);

    SET @Efficiency = @TotalCost * 1.0 / @RoundNum;

    RETURN @Efficiency;
END;
GO

WITH
    KillerEfficiency
    AS
    (
        SELECT
            k.Killer_ID,
            dbo.CalculateKillEfficiency(SUM(w.Cost), SUM(k.roundNum)) AS AvgKillEfficiency
        FROM
            Killer k
            INNER JOIN
            Weapons w ON k.Weapon_ID = w.Weapon_ID
        GROUP BY
        k.Killer_ID
    )

SELECT
    ke.Killer_ID,
    ke.AvgKillEfficiency
FROM
    KillerEfficiency ke
ORDER BY
    ke.AvgKillEfficiency ASC;

--13 Agent Popularity and Team Association Query
SELECT Agents.Agent_ID, COUNT(player.Player_ID) AS Player_Count, player.Team_ID
FROM Agents
   JOIN player ON Agents.Agent_ID = player.Agent_ID
GROUP BY Agents.Agent_ID, player.Team_ID
ORDER BY Player_Count DESC;

--14 Agent Selection Frequency by Winning Teams
SELECT player.Agent_ID, COUNT(*) AS Selection_Frequency
FROM player
   INNER JOIN matchteam ON player.Team_ID = matchteam.Team_ID
   INNER JOIN matches ON matchteam.Match_ID = matches.Match_ID
WHERE matchteam.side = matches.winningTeam
GROUP BY player.Agent_ID
ORDER BY Selection_Frequency DESC;

--15 Average Game Length for Each Map
SELECT matches.mapName, AVG(matches.gameLength) AS Average_Game_Length
FROM matches
GROUP BY matches.mapName;

--16 Agent Performance by Match Outcome
SELECT player.Agent_ID,
   SUM(CASE WHEN matchteam.side = matches.winningTeam THEN 1 ELSE 0 END) AS Wins,
   SUM(CASE WHEN matchteam.side != matches.winningTeam THEN 1 ELSE 0 END) AS Losses
FROM player
   INNER JOIN matchteam ON player.Team_ID = matchteam.Team_ID
   INNER JOIN matches ON matchteam.Match_ID = matches.Match_ID
GROUP BY player.Agent_ID;

--17 Player Performance Analysis
WITH
   Player_Kills
   AS
   (
       SELECT player.Player_ID, COUNT(killer.Kill_ID) AS Kills
       FROM player
           INNER JOIN killer ON player.Player_ID = killer.Killer_ID
       GROUP BY player.Player_ID
   )
SELECT Player_Kills.Player_ID, Player_Kills.Kills, weapons.Type
FROM Player_Kills
   INNER JOIN killer ON Player_Kills.Player_ID = killer.Killer_ID
   INNER JOIN weapons ON killer.Weapon_ID = weapons.Weapon_ID
ORDER BY Kills DESC;

--18 Agents Roles with Above Average Play rate/Popularity
WITH AgentPlayCounts AS (
    SELECT 
        a.agent_role,
        COUNT(*) AS PlayCount
    FROM player AS p
    JOIN Agents AS a ON p.Agent_ID = a.Agent_ID
    GROUP BY a.agent_role
)

SELECT 
    apc.agent_role,
    apc.PlayCount
FROM AgentPlayCounts AS apc
WHERE apc.PlayCount > (SELECT AVG(PlayCount) FROM AgentPlayCounts)
ORDER BY apc.PlayCount DESC;

--19 Agent Performance per Map
SELECT Matches.mapName, player.Agent_ID, COUNT(Killer.Kill_ID) AS Kill_Count
FROM Matches
JOIN MatchTeam ON Matches.Match_ID = MatchTeam.Match_ID
JOIN player ON MatchTeam.Team_ID = player.Team_ID
JOIN Killer ON player.Player_ID = Killer.Killer_ID
GROUP BY Matches.mapName, player.Agent_ID
ORDER BY Kill_Count DESC;

--20 Weapon Kills Analysis (total, average, min, max) Kills per Weapon
SELECT Weapons.Type,
       SUM(Kill_Count) AS Total_Kills,
       AVG(Kill_Count) AS Average_Kills,
       MIN(Kill_Count) AS Minimum_Kills,
       MAX(Kill_Count) AS Maximum_Kills
FROM (
  SELECT killer.Weapon_ID, COUNT(killer.Kill_ID) AS Kill_Count
  FROM killer
  GROUP BY killer.Weapon_ID
) AS KillData
JOIN Weapons ON KillData.Weapon_ID = Weapons.Weapon_ID
GROUP BY Weapons.Type;

--21 Count Average Kills Per Player for Each Agent
CREATE PROCEDURE GetAverageKillsPerPlayerForAgent
   @AgentID VARCHAR(50)
AS
BEGIN
   SELECT
       player.Player_ID,
       AVG(CAST(kill_count.Kills AS FLOAT)) AS Average_Kills
   FROM
       player
   INNER JOIN
       (SELECT Killer_ID, COUNT(Kill_ID) AS Kills FROM killer GROUP BY Killer_ID) kill_count ON player.Player_ID = kill_count.Killer_ID
   WHERE
       player.Agent_ID = @AgentID
   GROUP BY
       player.Player_ID;
END;
EXEC GetAverageKillsPerPlayerForAgent @AgentID = 'Jett';

--22 Weapon Usage and Effectiveness
SELECT Weapons.Weapon_ID, COUNT(Killer.kill_ID) AS Kill_Count
FROM Weapons
   JOIN Killer ON Weapons.Weapon_ID = Killer.Weapon_ID
GROUP BY Weapons.Weapon_ID
ORDER BY Kill_Count DESC;

--23 Most Effective Player-Agent Combinations
SELECT 
    player.Player_ID, 
    player.Agent_ID, 
    COUNT(*) AS GamesPlayed, 
    SUM(CASE WHEN matchTeam.side = matches.winningTeam THEN 1 ELSE 0 END) AS Wins,
    CONVERT(DECIMAL(5, 2), SUM(CASE WHEN matchTeam.side = matches.winningTeam THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0)) AS WinRate
FROM 
    player
JOIN 
    matchTeam ON player.Team_ID = matchteam.Team_ID
JOIN 
    matches ON matchteam.Match_ID = matches.Match_ID
GROUP BY 
    player.Player_ID, player.Agent_ID
ORDER BY 
    WinRate DESC, GamesPlayed DESC;

--24 Gun performance on each map
WITH MapWeaponKills AS (
   SELECT
       m.mapName,
       k.Weapon_ID,
       COUNT(k.Kill_ID) AS KillCount
   FROM
       Matches m
   JOIN
       MatchTeam mt ON m.Match_ID = mt.Match_ID
   JOIN
       Player p ON mt.Team_ID = p.Team_ID
   JOIN
       Killer k ON p.Player_ID = k.Killer_ID
   GROUP BY
       m.mapName, k.Weapon_ID
),
MaxKillsPerMap AS (
   SELECT
       mapName,
       MAX(KillCount) AS MaxKills
   FROM
       MapWeaponKills
   GROUP BY
       mapName
)
SELECT
   mwk.mapName,
   w.Weapon_ID,
   w.Type AS WeaponType,
   mwk.KillCount
FROM
   MapWeaponKills mwk
JOIN
   MaxKillsPerMap mkpm ON mwk.mapName = mkpm.mapName AND mwk.KillCount = mkpm.MaxKills
JOIN
   Weapons w ON mwk.Weapon_ID = w.Weapon_ID
ORDER BY
   mwk.mapName, mwk.KillCount DESC;

--25 Kill Count for each Agent
SELECT Agents.Agent_ID, COUNT(Killer.Kill_ID) AS Most_Kills 
FROM Agents
JOIN player ON player.Agent_ID = Agents.Agent_ID
JOIN Killer ON Killer.Killer_ID = player.Player_ID
JOIN Team ON Team.Team_ID = player.Team_ID
JOIN MatchTeam ON MatchTeam.Team_ID = Team.Team_ID
JOIN Matches ON Matches.Match_ID = MatchTeam.Match_ID
WHERE Matches.mapName = 'Ascent'
GROUP BY Agents.Agent_ID
ORDER BY Most_Kills DESC;

--26 Player Kill Counts Descending
SELECT player.Player_ID, COUNT(Killer.Kill_ID) AS Most_Kills 
FROM player
JOIN Killer ON Killer.Killer_ID = player.Player_ID
JOIN Team ON Team.Team_ID = player.Team_ID
JOIN MatchTeam ON MatchTeam.Team_ID = Team.Team_ID
JOIN Matches ON Matches
