USE warn
CREATE TABLE `fips` (
  `id` bigint(20) NOT NULL,
  `samecode` varchar(10) DEFAULT NULL,
  `polygon` mediumtext,
  PRIMARY KEY (`id`),
  KEY `fips_fips_IDX` (`samecode`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8
CREATE INDEX fips_samecode_IDX USING BTREE ON warn.fips (samecode)
