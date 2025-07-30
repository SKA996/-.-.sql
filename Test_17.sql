create procedure syn.usp_ImportFileCustomerSeasonal	--1: Нет комментария что выполняет данный скрипт.
	@Record_ID int
AS --2: Операторы и системные функции указываются в нижнем регистре.
set nocount on
begin
	declare @RowCount int = (select count(*) from syn.SA_CustomerSeasonal)	--3: Правила наименования переменных. переменная @RowCount Row вместо Rows правильно: @RowsCount
	declare @ErrorMessage varchar(max)	--4: Для объявления переменных declare используется один раз.  если не объявляем раннее объявленную переменную.
		--5: Рекомендуется при объявлении типов не использовать длину поля max
-- Проверка на корректность загрузки
	if not exists (
	select 1	--6: Содержимое exists оформляется с одним отступом.
	from syn.ImportFile as f	--7: Алиасы. При наименовании алиаса использовать первые заглавные буквы КАЖДОГО слова. В случае, если алиас представляет собой системное слово, добавляем первую согласную букву после заглавной: imf вместо f
	where f.ID = @Record_ID		
		and f.FlagLoaded = cast(1 as bit)
	)
		begin
			set @ErrorMessage = 'Ошибка при загрузке файла, проверьте корректность данных'

			raiserror(@ErrorMessage, 3, 1)
			return
		end

	--Чтение из слоя временных данных
	select
		c.ID as ID_dbo_Customer
		,cst.ID as ID_CustomerSystemType	--8: в алиасе не указанна схема. указывается, если объекты состоят в разных схемах.
		,s.ID as ID_Season
		,cast(cs.DateBegin as date) as DateBegin
		,cast(cs.DateEnd as date) as DateEnd
		,c_dist.ID as ID_dbo_CustomerDistributor
		,cast(isnull(cs.FlagActive, 0) as bit) as FlagActive
	into #CustomerSeasonal
	from syn.SA_CustomerSeasonal cs	--9: пропущенно ключевое слово AS при присвоении Алиаса
		join dbo.customer as c on c.UID_DS = cs.UID_DS_Customer	--10: Все виды join указываются явно.
			and c.ID_mapping_DataSource = 1 
		join dbo.Season as s on s.Name = cs.Season
		join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor
			and cd.ID_mapping_DataSource = 1
		join syn.CustomerSystemType as cst on cs.CustomerSystemType = cst.Name --11: При соединении таблиц сперва после on указываем поле присоединяемой таблицы.
	where try_cast(cs.DateBegin as date) is not null
		and try_cast(cs.DateEnd as date) is not null
		and try_cast(isnull(cs.FlagActive, 0) as bit) is not null

	-- Определяем некорректные записи								12:Многострочные комментарии (/* */) используются для развёрнутых пояснений:Открывающая и закрывающая части находятся на отдельных строках.
	-- Добавляем причину, по которой запись считается некорректной
	select
		cs.*
		,case
			when c.ID is null then 'UID клиента отсутствует в справочнике "Клиент"'
			when c_dist.ID is null then 'UID дистрибьютора отсутствует в справочнике "Клиент"'
			when s.ID is null then 'Сезон отсутствует в справочнике "Сезон"'
			when cst.ID is null then 'Тип клиента отсутствует в справочнике "Тип клиента"'
			when try_cast(cs.DateBegin as date) is null then 'Невозможно определить Дату начала'
			when try_cast(cs.DateEnd as date) is null then 'Невозможно определить Дату окончания'
			when try_cast(isnull(cs.FlagActive, 0) as bit) is null then 'Невозможно определить Активность'
		end as Reason
	into #BadInsertedRows
	from syn.SA_CustomerSeasonal as cs
	left join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer	--13: Отсутствует отступ.
		and c.ID_mapping_DataSource = 1
	left join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor and c_dist.ID_mapping_DataSource = 1
	left join dbo.Season as s on s.Name = cs.Season
	left join syn.CustomerSystemType as cst on cst.Name = cs.CustomerSystemType
	where cc.ID is null
		or cd.ID is null
		or s.ID is null
		or cst.ID is null
		or try_cast(cs.DateBegin as date) is null
		or try_cast(cs.DateEnd as date) is null
		or try_cast(isnull(cs.FlagActive, 0) as bit) is null

	-- Обработка данных из файла
	merge into syn.CustomerSeasonal as cs	--14: Перед названием таблицы, в которую осуществляется merge, into не указывается.
	using (	--15: Стандартные алиасы: Использовать t для целевой таблицы.
		select
			cs_temp.ID_dbo_Customer
			,cs_temp.ID_CustomerSystemType
			,cs_temp.ID_Season
			,cs_temp.DateBegin
			,cs_temp.DateEnd
			,cs_temp.ID_dbo_CustomerDistributor
			,cs_temp.FlagActive
		from #CustomerSeasonal as cs_temp
	) as s on s.ID_dbo_Customer = cs.ID_dbo_Customer
		and s.ID_Season = cs.ID_Season
		and s.DateBegin = cs.DateBegin
	when matched
		and t.ID_CustomerSystemType <> s.ID_CustomerSystemType then --16: then записывается на одной строке с when, независимо от наличия дополнительных условий.
		update
		set
			ID_CustomerSystemType = s.ID_CustomerSystemType
			,DateEnd = s.DateEnd
			,ID_dbo_CustomerDistributor = s.ID_dbo_CustomerDistributor
			,FlagActive = s.FlagActive
	when not matched then
		insert (ID_dbo_Customer, ID_CustomerSystemType, ID_Season, DateBegin, DateEnd, ID_dbo_CustomerDistributor, FlagActive)
		values (s.ID_dbo_Customer, s.ID_CustomerSystemType, s.ID_Season, s.DateBegin, s.DateEnd, s.ID_dbo_CustomerDistributor, s.FlagActive) --17: В конце MERGE всегда ставится ; .

	-- Информационное сообщение
	begin
		select @ErrorMessage = concat('Обработано строк: ', @RowCount)

		raiserror(@ErrorMessage, 1, 1)

		-- Формирование таблицы для отчетности
		select top 100
			Season as 'Сезон'
			,UID_DS_Customer as 'UID Клиента'
			,Customer as 'Клиент'
			,CustomerSystemType as 'Тип клиента'
			,UID_DS_CustomerDistributor as 'UID Дистрибьютора'
			,CustomerDistributor as 'Дистрибьютор'
			,isnull(format(try_cast(DateBegin as date), 'dd.MM.yyyy', 'ru-RU'), DateBegin) as 'Дата начала'
			,isnull(format(try_cast(DateEnd as date), 'dd.MM.yyyy', 'ru-RU'), DateEnd) as 'Дата окончания'
			,FlagActive as 'Активность'
			,Reason as 'Причина'
		from #BadInsertedRows

		return
	end

end
