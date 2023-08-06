/*
	-- DOCHÁZKA – PŘESČASY
    
    -- INSTALACE: stačí spustit tento krátký skript.
    
    -- Spustí měření. Pokud už nějaké běží, nedělá nic. Vrací už odpracovaný čas za den.
    CALL overtime.run();
    
    -- Ukončí měření, pokud nějaké běží. Vrací odpracovaný čas za den.
	CALL overtime.pause();
    
    -- Vím, že budu končit za 10 minut.
	CALL overtime.pausePlus('0:10');
    
    -- Zobrazí dnešní měření.
    SELECT * FROM overtime.log where dt = CURRENT_DATE() order by `start`;
    
    -- Report za poslední měsíc.
	SELECT * FROM overtime.report_last_month;
    
    -- Součty za poslední měsíc.
	SELECT * FROM overtime.sum_last_month;
    
    -- Součty za tento měsíc do včerejšího dne.
	SELECT * FROM overtime.sum_this_month;
    
    -- Ruční zadání osmihodinové práce začínající v sedm ráno.
    insert into overtime.log (dt, `start`, total) values ('2017-05-02', '07:00', '08:00');
    
    -- Ruční zadání jednodenní dovolené (vícedenní rozsah není možné zadávat).
    insert into overtime.log (`type`, dt, `start`, total) values ('holiday', '2017-06-14', '08:00', '08:00');

    -- Ruční zadání návštěvy lékaře.
    insert into overtime.log (`type`, dt, `start`, `end`, note) values ('other', '2017-07-18', '13:38', '15:04', 'Návštěva lékaře');
    
     -- Příklad zadání volných dní (svátků).
	insert ignore freeday (dt) values ('2017-07-05'),('2017-07-06'),('2017-09-28');

    -- Pokud je práce ve dni volna připadajícího na den po-pá, musí se upravit sumec.target na 0 (o svátcích aplikace nic neví, pokud nejsou v tabulce freeday).
*/

CREATE DATABASE IF NOT EXISTS `overtime`; -- DEFAULT CHARACTER SET utf8 COLLATE utf8_czech_ci;

USE overtime;

CREATE TABLE IF NOT EXISTS `sumec` ( -- součty za den
	`dt` date not null,
	`target` time not null default '08:00', -- NORMA 8h
    `overtime` time, -- přesčas
    `free` time, -- den volna
	`total` time, -- celkem za den
	PRIMARY KEY (`dt`),
	KEY `total` (`total`),    
	KEY `target` (`target`),    
	KEY `overtime` (`overtime`),    
	KEY `free` (`free`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `log` (
	`id` int(11) unsigned NOT NULL AUTO_INCREMENT,
	`type` ENUM('job','holiday','other') NOT NULL DEFAULT 'job',
	`dt` date not null,
	`start` time not null,
	`end` time,
	`total` time,
	`note` varchar(255),
	PRIMARY KEY (`id`),
	KEY `dt` (`dt`),
	KEY `type` (`type`),
	KEY `total` (`total`),
	FOREIGN KEY (`dt`) REFERENCES sumec (dt) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `freeday` ( -- tabulka svátků – předpis pro nastavení sumec.target=0
	`dt` date not null,
	`note` varchar(255),
    PRIMARY KEY (`dt`)
) ENGINE=InnoDB;

insert ignore freeday (dt) values -- example of days off
('2017-07-05'),('2017-07-06'),('2017-09-28'),('2017-11-17'),('2017-12-25'),('2017-12-26');

DROP view IF EXISTS `report_last_month`;
create view report_last_month as
select 
WEEKDAY(log.dt) +1 `den v týdnu`, log.dt `datum`, log.`start` `začátek`, log.`end` `konec`, log.`total` `celkem`, 
cast(time_to_sec(log.`total`) / (60 * 60) as decimal(10, 2)) `celkem hodin`,
sumec.target `norma`, TIME_FORMAT(sumec.overtime, '%T') `přesčas`, sumec.free `den volna`, sumec.total as `celkem za den`, 
log.`type` `druh`, ifnull(log.note, '') `poznámka`
from log
join sumec on sumec.dt = log.dt
WHERE log.dt BETWEEN 
		ADDDATE(LAST_DAY(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH)), INTERVAL 1 DAY)
		AND 
		ADDDATE(LAST_DAY(DATE_SUB(CURRENT_DATE(),INTERVAL 1 MONTH)), INTERVAL 0 DAY)
order by log.dt, log.`start`;

DROP view IF EXISTS `sum_last_month`;
create view sum_last_month as
SELECT 
SEC_TO_TIME(SUM(TIME_TO_SEC(target))) `norma`,
TIME_FORMAT(SEC_TO_TIME(SUM(TIME_TO_SEC(overtime))), '%T') `přesčas`,
SEC_TO_TIME(SUM(TIME_TO_SEC(free))) `den volna`,
SEC_TO_TIME(SUM(TIME_TO_SEC(total))) `celkem za měsíc`
FROM overtime.sumec 
WHERE dt BETWEEN 
	ADDDATE(LAST_DAY(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH)), INTERVAL 1 DAY)
	AND 
	ADDDATE(LAST_DAY(DATE_SUB(CURRENT_DATE(),INTERVAL 1 MONTH)), INTERVAL 0 DAY);
    
DROP view IF EXISTS `sum_this_month`; -- tento měsíc do včerejšího dne
create view sum_this_month as
SELECT 
SEC_TO_TIME(SUM(TIME_TO_SEC(target))) `norma`,
SEC_TO_TIME(SUM(TIME_TO_SEC(overtime))) `přesčas`,
SEC_TO_TIME(SUM(TIME_TO_SEC(free))) `den volna`,
SEC_TO_TIME(SUM(TIME_TO_SEC(total))) `celkem za měsíc`
FROM overtime.sumec 
WHERE dt BETWEEN 
	ADDDATE(LAST_DAY(DATE_SUB(CURRENT_DATE(),INTERVAL 1 MONTH)), INTERVAL 1 DAY)
	AND 
	DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY); -- do včera    

DROP PROCEDURE IF EXISTS calc_sumec;
delimiter |
CREATE PROCEDURE calc_sumec(_dt date)
BEGIN
	
	update sumec set 
    total = (
		select SEC_TO_TIME(sum(TIME_TO_SEC(total)))
		from log where dt = _dt and total is not null
	)
	where dt = _dt;
    
    update sumec set overtime = TIMEDIFF(total, target)
    where dt = _dt and total is not null;
    
    update sumec set free = if(target = 0, TIMEDIFF(total, target), 0) 
    where dt = _dt and total is not null;
  
END|
delimiter ;

DROP TRIGGER IF EXISTS log_before_insert;
delimiter |
CREATE TRIGGER log_before_insert BEFORE INSERT ON log
FOR EACH ROW
BEGIN
	
    if (new.`dt` is null) then SET NEW.`dt` = current_date(); end if;
    if (new.`start` is null) then SET NEW.`start` = current_time(); end if;
    
    insert ignore into sumec(dt, target) values (new.dt, time_target(new.dt)); 
    
    -- konec nemůže být menší než začátek, leda by to někdo stopnul druhý den ráno
    if (new.`start` > new.`end`) then 
		set new.`end` = '23:59';
    end if;
    
    if (new.`end` is null and new.total is not null) then 
		set new.`end` = ADDTIME(new.`start`, new.total);
    end if;
    
    if (new.`end` is not null) then 
        set new.`total` = TIMEDIFF(new.`end`, new.`start`);
    end if;    
    
END|
delimiter ;

DROP TRIGGER IF EXISTS log_after_insert;
delimiter |
CREATE TRIGGER log_after_insert AFTER INSERT ON log
FOR EACH ROW
BEGIN
	call calc_sumec(new.dt);
END|
delimiter ;

DROP TRIGGER IF EXISTS log_before_update;
delimiter |
CREATE TRIGGER log_before_update BEFORE UPDATE ON log
FOR EACH ROW
BEGIN

	-- konec nemůže být menší než začátek, leda by to někdo stopnul druhý den ráno
	if (new.`start` > new.`end`) then
		set new.`end` = '23:59'; 
    end if;

	if (new.total != old.total or (new.total is not null and old.total is null)) then
		set new.`end` = ADDTIME(new.`start`, new.total);
    end if;

	set new.`total` = TIMEDIFF(new.`end`, new.`start`);
    
END|
delimiter ;

DROP TRIGGER IF EXISTS log_after_update;
delimiter |
CREATE TRIGGER log_after_update AFTER UPDATE ON log
FOR EACH ROW
BEGIN
	call calc_sumec(new.dt);
END|
delimiter ;

DROP TRIGGER IF EXISTS sumec_before_update;
delimiter |
CREATE TRIGGER sumec_before_update BEFORE UPDATE ON sumec
FOR EACH ROW
BEGIN

	set new.overtime = TIMEDIFF(new.total, new.target);
	set new.free = if(new.target = 0, TIMEDIFF(new.total, new.target), CAST(0 as time));
    
END|
delimiter ;

DROP TRIGGER IF EXISTS log_after_delete;
delimiter |
CREATE TRIGGER log_after_delete AFTER DELETE ON log
FOR EACH ROW
BEGIN
	call calc_sumec(old.dt);
END|
delimiter ;

DROP PROCEDURE IF EXISTS run;
delimiter |
CREATE PROCEDURE run()
BEGIN

	declare _id int(11) unsigned;
	declare _total time;
	declare _open time;
	declare _last_end time;
	
    set _id = (select id from log where `end` is null limit 1);
	
    if (_id is null) then begin -- předchozí měření už skončilo
		set _last_end = (select max(`end`) from log where dt = current_date());
		insert into log (`start`) values ( if(_last_end > current_time(), _last_end, current_time()) );
        set _id = (select LAST_INSERT_ID());
    end; end if;
    
    set _total = (select SEC_TO_TIME(sum(TIME_TO_SEC(total))) 
    from log where dt = CURRENT_DATE() and total is not null);
    
    set _open = (select TIMEDIFF(current_time(), `start`)  from log where `end` is null);
    
    set _total = ADDTIME( CAST(ifnull(_total, 0) AS time), CAST(ifnull(_open, 0) AS time) );
    
    select _total `celkem za den`, cast(time_to_sec(_total) / (60 * 60) as decimal(10, 2)) `hodin`;
  
END|
delimiter ;

DROP PROCEDURE IF EXISTS pause;
delimiter |
CREATE PROCEDURE pause()
BEGIN
	
    update log set `end` = current_time() where `end` is null;    
    
    select total `celkem za den`, cast(time_to_sec(total) / (60 * 60) as decimal(10, 2)) `hodin`
    from sumec where dt = CURRENT_DATE();
  
END|
delimiter ;

DROP PROCEDURE IF EXISTS pausePlus;
delimiter |
CREATE PROCEDURE pausePlus(_add time)
BEGIN
	
    update log set `end` = ADDTIME(current_time(), _add) where `end` is null;    
    
    select total `celkem za den`, cast(time_to_sec(total) / (60 * 60) as decimal(10, 2)) `hodin`
    from sumec where dt = CURRENT_DATE();
  
END|
delimiter ;

DROP FUNCTION IF EXISTS `time_target`;
DELIMITER |
CREATE FUNCTION `time_target`(_dt date) 
RETURNS time
BEGIN
	declare result time;    
	
	if (select 1=1 from freeday where dt = _dt limit 1) then
		set result = '00:00'; -- svátek
	else -- sobota a neděle je automaticky norma 0, jinak 8h
		set result = if (WEEKDAY(_dt) +1 > 5, '00:00','08:00');
    end if;
    
    return result;
END |
DELIMITER ;
