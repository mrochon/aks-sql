using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

app.MapGet("/", async (IConfiguration config) =>
{
    var htmlResponse = "<html><body>";
    htmlResponse += "<h1>Hello World from AKS!</h1>";
    
    // Test database connection using Entra authentication with federated token
    try
    {
        var connectionString = config["ConnectionStrings:SqlDatabase"];
        
        if (!string.IsNullOrEmpty(connectionString))
        {
            using var connection = new SqlConnection(connectionString);
            
            // Use DefaultAzureCredential which supports workload identity (federated tokens)
            var credential = new DefaultAzureCredential();
            var token = await credential.GetTokenAsync(
                new TokenRequestContext(new[] { "https://database.windows.net/.default" }));
            
            connection.AccessToken = token.Token;
            await connection.OpenAsync();
            
            using var command = new SqlCommand("SELECT GETDATE() as CurrentDateTime", connection);
            var result = await command.ExecuteScalarAsync();
            
            htmlResponse += $"<p style='color: green;'>✓ Database connection successful!</p>";
            htmlResponse += $"<p>Database time: {result}</p>";
        }
        else
        {
            htmlResponse += "<p style='color: orange;'>⚠ No database connection string configured</p>";
        }
    }
    catch (Exception ex)
    {
        htmlResponse += $"<p style='color: red;'>✗ Database connection failed: {ex.Message}</p>";
    }
    
    htmlResponse += "</body></html>";
    
    return Results.Content(htmlResponse, "text/html");
});

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();
