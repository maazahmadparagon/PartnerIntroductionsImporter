-- Adds the columns used by PolicyLink lead support to dbo.PartnerLeads.
-- Run once against the [Phone System] database BEFORE deploying the updated importer.
-- All columns are nullable, so existing rows and other partners are unaffected.
-- Safe to re-run: each column is only added if it doesn't already exist.

USE [Phone System];
GO

IF COL_LENGTH('dbo.PartnerLeads', 'Title') IS NULL
    ALTER TABLE dbo.PartnerLeads ADD Title NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.PartnerLeads', 'FirstName') IS NULL
    ALTER TABLE dbo.PartnerLeads ADD FirstName NVARCHAR(100) NULL;
IF COL_LENGTH('dbo.PartnerLeads', 'LastName') IS NULL
    ALTER TABLE dbo.PartnerLeads ADD LastName NVARCHAR(100) NULL;
IF COL_LENGTH('dbo.PartnerLeads', 'Product') IS NULL
    ALTER TABLE dbo.PartnerLeads ADD Product NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.PartnerLeads', 'CoverDate') IS NULL
    ALTER TABLE dbo.PartnerLeads ADD CoverDate NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.PartnerLeads', 'PropertyUse') IS NULL
    ALTER TABLE dbo.PartnerLeads ADD PropertyUse NVARCHAR(100) NULL;
IF COL_LENGTH('dbo.PartnerLeads', 'Source') IS NULL
    ALTER TABLE dbo.PartnerLeads ADD Source NVARCHAR(50) NULL;
GO
