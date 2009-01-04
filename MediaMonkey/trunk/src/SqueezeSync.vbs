    Option Explicit
    '1. Save this text as 'SqueezeSync.vbs' in the Scripts-folder of MediaMonkey
    '2. Add this Section to Scripts.ini

    '[SqueezeSync]
    'FileName=SqueezeSync.vbs
    'ProcName=SqueezeSync
    'DisplayName=SqueezeSync
    'Language=VBScript
    'ScriptType=0

    '3. Edit the path to your playcounter-file in the code below.
    '4. Restart MediaMonkey
    '5. You'll find "PlayCountImport" under Tools/Scripts

    'Public Const path = "F:\Ben Howard's Documents\My Music\Trackstat\TrackStat_iTunes_Hist.txt" 'PUT THE PATH TO YOUR FILE HERE

    Sub SqueezeSync(path)
       Dim str, arr, songpath, sit, itm, playdate, newrate, pldat, propdat
       Dim fso : Set fso = CreateObject("Scripting.FileSystemObject")
       if fso.FileExists(path) then
          Dim txt : Set txt = fso.OpenTextFile(path,1,False)
          SDB.Database.BeginTransaction
          Do While Not txt.AtEndOfStream
             SDB.ProcessMessages
             str = Trim(txt.ReadLine)
             arr = Split(str,"|")

    'arr(0) is Title
    'arr(1)
    'arr(2)
    'arr(3) is SongPath
    'arr(4) is Played or Rated
    'arr(5) is Date in this format 20081209074549 yyyymmddhhmmss

    'arr(6) is Rating

             songpath = Mid(arr(3),2)
             newrate = arr(6)
             Set sit = SDB.Database.QuerySongs("AND (Songs.SongPath = '"&Replace(songpath,"'","''")&"')")
             If Not (sit.EOF) Then
                Set itm = sit.Item
                if arr(4) = "rated" then
                   itm.rating = newrate
                else
                      itm.Playcounter = itm.Playcounter + 1
                      pldat = arr(5)
                         propdat = Left(pldat, 4) & "-" & Mid(pldat, 5, 2) & "-" & Mid(pldat, 7, 2) & " " & mid(pldat, 9, 2) & ":" & mid(pldat, 11, 2) & ":" & right(pldat, 2)
                         playdate = FormatDateTime(propdat)
                     if DateValue(itm.LastPlayed) < DateValue(playdate) then
                        itm.LastPlayed = playdate
                     end if
              end if
             itm.UpdateDB
             End If
          Loop
          Set sit = Nothing
          SDB.Database.Commit
       else
        exit sub
       end if
    End sub

