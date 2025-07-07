class ModeFigure8 : public Mode
{
public:

    Number mode_number() const override { return Number::FIGURE8; }
    const char *name() const override { return "FIGURE8"; }
    const char *name4() const override { return "FIG8"; }

    void update() override;

protected:
    bool _enter() override;

private:
    int8_t direction = 1;
    uint32_t last_switch_ms = 0;
    static constexpr uint32_t switch_period_ms = 5000;
};
