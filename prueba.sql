use bantotal_Repl


/*INTEGRANTES*/

select Ctnro, Pendoc, Petdoc, COUNT(distinct Pfndo1) as NroIPJ
	into #Integrantes
	from FSR008
		left join FSR003 on Pendoc=Pjndoc
	group by Ctnro, Pendoc, Petdoc

--select * from #Integrantes where Ctnro=2238

/*CLIENTES MCF*/

select distinct Aocta as Cuenta, Pendoc as Documento, NroIPJ, Pfndo1 as Integrante, Petdoc as TipoDoc, MAX(Aofval) as MaxFchVal, 
	SUM(case when Aostat=0 then 1 else 0 end) as VigentesMCF, COUNT(distinct Aooper) as OpMCF, 
	Min(case when Aostat=99 then Aofvto else '1753-01-01 00:00:00.000' end ) as UltimoVtoCanceladas,
	MAX(JRPM4DiMorAct) as MaxAtrasoVig, MIN(Aofval) as PrimerFchVal, 
	MAX(FLOOR((case when Aomda=0 then Aoimp when Aomda=2225 then Aoimp*ISNULL(Cotcbi, 30) else 0 end))) as MaxImp
	into #ResumenMCF
	from FSD010
		join JRPM004 on JRPM4Cuent=Aocta and JRPM4Opera=Aooper and JRPM4Modul=Aomod and JRPM4TipOp=Aotope and JRPM4SubOp=Aosbop and Jrpm4LinNeg=3
		join #Integrantes on Ctnro=Aocta
		left join FSR003 on Pjndoc=Pendoc and NroIPJ=1 and Pftdo1=1 -- Solamente ofrecemos el producto a CI o RUT de un integrante
		left join FSH005 on Cofdes=Aofval and Moneda=2225
	where ((Aomod in (101) and Aotope in (1,25,26, 19, 29)) or
				(Aomod in (102) and Aotope in (1,3,30)) or (Aomod in (103) and Aotope in (1,7)) or 
				(Aomod in (104) and Aotope in (1,30)))
			 and Aostat in (0, 99) and Aocta<>89429 -- Patricia Cleffi
	and year(Aofval)=2019 
	group by Aocta, Pendoc, NroIPJ, Pfndo1, Petdoc
	having SUM(case when Aostat=99 then 1 else 0 end)>=0

				


	select * 
	into #Datos
	from #ResumenMCF
	--where UltimoVtoCanceladas<MaxFchVal
	--and UltimoVtoCanceladas<>'1753-01-01 00:00:00.000'


	/*ATRASO PREVIO A MI OP*/
                 
select pp.Ppcta, pp.Ppoper, pp.Ppmod, pp.Pptope, pp.Ppsbop, pp.Ppfpag, MAX(Pp1fech) as Pp1fech,MaxFchVal, MAX(ISNULL(Pp1fech, MaxFchVal)) as Aux,
	case when DATEDIFF(DD, pp.Ppfpag, case when MAX(Pp1fech)>MaxFchVal or MAX(Pp1fech)  is null then MaxFchVal else MAX(Pp1fech)  end)>0 
		then DATEDIFF(DD, pp.Ppfpag, case when MAX(Pp1fech)>MaxFchVal or MAX(Pp1fech)  is null then MaxFchVal else MAX(Pp1fech)  end) else 0 end as Atraso,
		1 as cuota
		
	into #AtrasoCuota
	from FSD601 pp
		join #Datos on pp.Ppcta=Cuenta
		join FSD010 on pp.Ppcta=Aocta and pp.Ppoper=Aooper and pp.Ppsbop=Aosbop and Aostat in (0, 99) 
		left join FSD602 pag on pp.Ppcta=pag.Ppcta and pp.Ppoper=pag.Ppoper and pp.Ppmod=pag.Ppmod and pp.Pptope=pag.Pptope and pp.Ppsbop=pag.Ppsbop
				and pp.Ppfpag=pag.Ppfpag and pp.Pptipo=pag.Pptipo and Pp1stat='T' 
	where pp.Ppmod in (101, 102, 103, 104, 111, 112, 113, 114) -- Saco dto. de documentos
	and pp.Ppcap+pp.Ppint>0 -- Para sacar las cuotas con importe 0
	and pp.D601co='S' -- Cuotas que están OK
	--and pp.Ppcta in (48796) and pp.Ppoper in (197702, 185049)
	and pp.Ppfpag<=MaxFchVal 
	group by pp.Ppcta, pp.Ppoper, pp.Ppmod, pp.Pptope, pp.Ppsbop, pp.Ppfpag, MaxFchVal


select distinct Ppcta, COUNT(distinct Ppoper) as '#Op'
	from #AtrasoCuota
	group by Ppcta


select Ppcta, Ppoper, Ppmod, SUM(Cuota) as CuotasAtraso, CAST(CAST(SUM(Atraso) as float)/SUM(Cuota) as float) as AtrasoOperacion, 
	MAX(Atraso) as AtrasoMax
	into #AtrasoOperacion
	from #AtrasoCuota
	where (Ppfpag<=MaxFchVal or (Pp1fech is not NULL and Pp1fech<=MaxFchVal)) 
	--and Ppcta=80504
	group by Ppcta, Ppoper, Ppmod


select j.Ppcta, round(SUM(cast(AtrasoOperacion as float))/COUNT(*),2) as Atraso_cuenta, 
	isnull(Atraso_vigente,0) as Atraso_vigente, isnull(Atraso_maximo,0) as Atraso_maximo, isnull(Atraso_ultpago,0) as Atraso_ultpago
	into #Atraso_Previo
	from #AtrasoOperacion j
		left join (select Ppcta, Max(Atraso) as Atraso_vigente
					from #AtrasoCuota
					where (Ppfpag<=MaxFchVal and (Pp1fech is NULL or Pp1fech>=MaxFchVal)) 
					group by Ppcta) jj on jj.Ppcta=j.Ppcta
		left join (select Ppcta, Max(Atraso) as Atraso_maximo
					from #AtrasoCuota
					where (Ppfpag<=MaxFchVal)
					group by Ppcta) jjj on jjj.Ppcta=j.Ppcta
	    left join (select f.Ppcta, Max(Atraso) as Atraso_ultpago
					from #AtrasoCuota f
						join (select Ppcta, MAX(Pp1fech) as MaxPp1fech 
								from #AtrasoCuota
								where Pp1fech is not NULL and Pp1fech<=MaxFchVal
								group by Ppcta) h on  f.Ppcta=h.Ppcta and  h.MaxPp1fech=f.Pp1fech
					where (Ppfpag<=MaxFchVal)
					group by f.Ppcta) jjjj on jjjj.Ppcta=j.Ppcta
	group by j.Ppcta, Atraso_vigente, Atraso_maximo, Atraso_ultpago




	
	--select *, case when  MaxFchVal<Pp1fech then datediff(dd, MaxFchVal,Pp1fech) else 0 end as AtrasoVigente 
	--into #Atraso2
	--from #AtrasoCuota
	--order by Ppcta, Ppoper, Ppfpag

--select j.* 
----into #CasosInteres
--from #Atraso2 j
--join (
--select Ppcta, max(Pp1fech) as Fecha
--from #Atraso2
--group by Ppcta ) h on h.Ppcta=j.Ppcta and h.Fecha=j.Pp1fech
--where Atraso>4 and j.Ppcta not in (select distinct ppcta from #AtrasoCuota
--where Atraso>60)

/*ATRASO POSTERIOR A LA OP - 1 AÑO*/
                 
select pp.Ppcta, pp.Ppoper, pp.Ppmod, pp.Pptope, pp.Ppsbop, pp.Ppfpag, MAX(pag.Pp1fech) as Pp1fech,MaxFchVal, MAX(ISNULL(pag.Pp1fech, GETDATE())) as Aux,
	case when DATEDIFF(DD, pp.Ppfpag, case when MAX(Pp1fech)>dateadd(yy,1,MaxFchVal)  or MAX(Pp1fech)  is null then dateadd(yy,1,MaxFchVal) else MAX(Pp1fech)  end)>0 
		then DATEDIFF(DD, pp.Ppfpag, case when MAX(Pp1fech)>dateadd(yy,1,MaxFchVal)  or MAX(Pp1fech)  is null then dateadd(yy,1,MaxFchVal) else MAX(Pp1fech)  end) else 0 end as Atraso,
	1 as Cuota
	into #AtrasoCuota2
	from FSD601 pp
		join #Datos on pp.Ppcta=Cuenta
		join FSD010 on pp.Ppcta=Aocta and pp.Ppoper=Aooper and pp.Ppsbop=Aosbop and Aostat in (0, 99) 
		left join FSD602 pag on pp.Ppcta=pag.Ppcta and pp.Ppoper=pag.Ppoper and pp.Ppmod=pag.Ppmod and pp.Pptope=pag.Pptope and pp.Ppsbop=pag.Ppsbop
				and pp.Ppfpag=pag.Ppfpag and pp.Pptipo=pag.Pptipo and Pp1stat='T' 
	where pp.Ppmod in (101, 102, 103, 104, 111, 112, 113, 114) -- Saco dto. de documentos
	and pp.Ppcap+pp.Ppint>0 -- Para sacar las cuotas con importe 0
	and pp.D601co='S' -- Cuotas que están OK
	--and pp.Ppcta in (48796) and pp.Ppoper in (197702, 185049)
	and pp.Ppfpag>MaxFchVal and pp.Ppfpag<=dateadd(yy,1,MaxFchVal) 
	and pp.Ppcta in (select distinct Ppcta from #Atraso_Previo)  
	group by pp.Ppcta, pp.Ppoper, pp.Ppmod, pp.Pptope, pp.Ppsbop, pp.Ppfpag, MaxFchVal



select Ppcta, Ppoper, Ppmod, SUM(Cuota) as CuotasAtraso, CAST(CAST(SUM(Atraso) as float)/SUM(Cuota) as float) as AtrasoOperacion, 
	MAX(Atraso) as AtrasoMax
	into #AtrasoOperacion2
	from #AtrasoCuota2
	where (Ppfpag<=dateadd(yy,1,MaxFchVal)  or (Pp1fech is not NULL and Pp1fech<=dateadd(yy,1,MaxFchVal) )) 
	--and Ppcta=80504
	group by Ppcta, Ppoper, Ppmod



select j.Ppcta, round(SUM(cast(AtrasoOperacion as float))/COUNT(*),2) as Atraso_cuenta, 
	isnull(Atraso_vigente,0) as Atraso_vigente, isnull(Atraso_maximo,0) as Atraso_maximo, isnull(Atraso_ultpago,0) as Atraso_ultpago
	into #Atraso_Posterior
	from #AtrasoOperacion2 j
		left join (select Ppcta, Max(Atraso) as Atraso_vigente
					from #AtrasoCuota2
					where (Ppfpag<=dateadd(yy,1,MaxFchVal) and (Pp1fech is NULL or Pp1fech>=dateadd(yy,1,MaxFchVal) ))
					group by Ppcta) jj on jj.Ppcta=j.Ppcta
		left join (select Ppcta, Max(Atraso) as Atraso_maximo
					from #AtrasoCuota2
					where (Ppfpag<=dateadd(yy,1,MaxFchVal) )
					group by Ppcta) jjj on jjj.Ppcta=j.Ppcta
	    left join (select f.Ppcta, Max(Atraso) as Atraso_ultpago
					from #AtrasoCuota2 f
						join (select Ppcta, MAX(Pp1fech) as MaxPp1fech 
								from #AtrasoCuota2
								where Pp1fech is not NULL and Pp1fech<=dateadd(yy,1,MaxFchVal) 
								group by Ppcta) h on  f.Ppcta=h.Ppcta and  h.MaxPp1fech=f.Pp1fech
					where (Ppfpag<=dateadd(yy,1,MaxFchVal) )
					group by f.Ppcta) jjjj on jjjj.Ppcta=j.Ppcta
	group by j.Ppcta, Atraso_vigente, Atraso_maximo, Atraso_ultpago



	select * from #Atraso_Previo
	where Atraso_ultpago<=4

	select * from #Atraso_Previo
	where Atraso_ultpago>4

	select * from #Atraso_Posterior

	select * from jrpy418
	where JRPY418Subsanable='S'