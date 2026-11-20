local Home = {}

function Home.model(reading, now)
    reading = reading or {}
    return {
        current = reading[1],
        more = reading[2],
        reading_count = #reading,
        now = now,
    }
end

return Home
